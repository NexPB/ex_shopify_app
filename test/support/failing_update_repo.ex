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

  @doc "Always fail, simulating a durable write failure after a successful refresh."
  def update(_changeset), do: {:error, :persist_boom}
end

defmodule ExShopifyApp.FailingStore do
  @moduledoc "Store whose refresh path persists through the failing repo shim."

  use ExShopifyApp.AccessToken.Repo, repo: ExShopifyApp.FailingUpdateRepo
end
