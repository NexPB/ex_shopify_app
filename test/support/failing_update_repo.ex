defmodule ExShopifyApp.FailingUpdateRepo do
  @moduledoc """
  A repo shim that behaves exactly like `ExShopifyApp.TestRepo` except that `update/1`
  fails. Used to drive the "Shopify returned a token but the durable write failed" path
  without tearing down the real database.

  Every `update/1` fails unless `fail_updates/1` limits the failures. Tag a test with
  `@tag failed_updates: n` to call it from the `RepoTest` setup.

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

  @doc """
  Fail only the next `count` calls to `update/1`, then delegate to `TestRepo`.

  The limit is global, so only `async: false` tests may set it. `reset/0` removes it.
  """
  def fail_updates(count) when is_integer(count) and count >= 0 do
    counter = :counters.new(1, [])
    :counters.put(counter, 1, count)
    :persistent_term.put(__MODULE__, counter)
  end

  @doc "Remove the limit that `fail_updates/1` set, so every `update/1` fails again."
  def reset, do: :persistent_term.erase(__MODULE__)

  @doc "Fail, simulating a durable write failure after a successful refresh."
  def update(changeset) do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        {:error, :persist_boom}

      counter ->
        if :counters.get(counter, 1) > 0 do
          :counters.sub(counter, 1, 1)
          {:error, :persist_boom}
        else
          TestRepo.update(changeset)
        end
    end
  end
end

defmodule ExShopifyApp.FailingStore do
  @moduledoc "Store whose refresh path persists through the failing repo shim."

  use ExShopifyApp.AccessToken.Repo, repo: ExShopifyApp.FailingUpdateRepo
end
