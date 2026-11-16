defmodule ExShopifyApp.FailingUpdateRepo do
  @moduledoc """
  A repo shim that behaves exactly like `ExShopifyApp.TestRepo` except that `update/1`
  always fails. Used to drive the "Shopify returned a token but the durable write
  failed" path without tearing down the real database.

  Reads, the row lock, the surrounding transaction, and `rollback/1` all delegate to
  `TestRepo`, so the FOR UPDATE lock and transaction semantics are real; only the final
  write is forced to fail.
  """

  alias ExShopifyApp.TestRepo

  defdelegate get(schema, id), to: TestRepo
  defdelegate one(query), to: TestRepo
  defdelegate insert(changeset, opts), to: TestRepo
  defdelegate update_all(query, updates), to: TestRepo
  defdelegate query!(sql), to: TestRepo
  defdelegate transaction(fun, opts), to: TestRepo
  defdelegate rollback(value), to: TestRepo
  defdelegate in_transaction?(), to: TestRepo

  @doc "Always fail, simulating a durable write failure after a successful refresh."
  def update(_changeset), do: {:error, :persist_boom}
end

defmodule ExShopifyApp.FailingStore do
  @moduledoc "Store whose refresh path persists through the failing repo shim."

  use ExShopifyApp.AccessToken.Repo, repo: ExShopifyApp.FailingUpdateRepo
end

defmodule ExShopifyApp.FailingOnceUpdateRepo do
  @moduledoc """
  A repo shim like `ExShopifyApp.FailingUpdateRepo`, except that only the first
  `update/1` in a process fails. Both refresh runs execute in the same supervised task.
  """

  alias ExShopifyApp.TestRepo

  defdelegate get(schema, id), to: TestRepo
  defdelegate one(query), to: TestRepo
  defdelegate insert(changeset, opts), to: TestRepo
  defdelegate update_all(query, updates), to: TestRepo
  defdelegate query!(sql), to: TestRepo
  defdelegate transaction(fun, opts), to: TestRepo
  defdelegate rollback(value), to: TestRepo
  defdelegate in_transaction?(), to: TestRepo

  @doc "Fail the first call in the calling process, then delegate to `TestRepo`."
  def update(changeset) do
    if Process.put(:failing_once_update_repo, :failed) do
      TestRepo.update(changeset)
    else
      {:error, :persist_boom}
    end
  end
end

defmodule ExShopifyApp.FailingOnceStore do
  @moduledoc "Store whose first write after a refresh fails."

  use ExShopifyApp.AccessToken.Repo, repo: ExShopifyApp.FailingOnceUpdateRepo
end
