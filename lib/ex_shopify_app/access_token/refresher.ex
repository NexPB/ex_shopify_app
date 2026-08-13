defmodule ExShopifyApp.AccessToken.Refresher do
  @moduledoc """
  Runs a locked token mutation in a supervised task, off the calling process.

  Shopify invalidates the previous refresh token the moment it answers, so the
  transaction that persists the new one *must* commit. On the caller's process it might
  not: Ecto checks connections out per process, so a caller already inside its own
  `Repo.transaction/2` nests the refresh and can roll the new token away, and a caller
  killed mid-refresh takes the open transaction down with it.

  `Task.Supervisor.async_nolink/2` gives the mutation its own connection — a top-level
  transaction — and no link back to the caller. The task is never `Task.shutdown/2`-ed:
  abandoning the wait leaves it running, because its commit is the thing worth
  protecting. Callers wait indefinitely, bounded by the transaction's own `:timeout`.
  """

  require Logger

  @supervisor ExShopifyApp.AccessToken.TaskSupervisor

  @doc """
  Run `fun` under `ExShopifyApp.AccessToken.TaskSupervisor` and wait for its result.

  Returns whatever `fun` returns, or `{:error, {:refresh_unavailable, reason}}` if the
  task exits abnormally. Logs a warning when `repo` is already in a transaction on the
  calling process.
  """
  @spec run(module(), String.t(), (-> result)) ::
          result | {:error, {:refresh_unavailable, term()}}
        when result: term()
  def run(repo, domain, fun) when is_function(fun, 0) do
    warn_if_in_transaction(repo, domain)

    @supervisor
    |> Task.Supervisor.async_nolink(fun)
    |> await()
  end

  defp await(task) do
    case Task.yield(task, :infinity) do
      {:ok, result} -> result
      {:exit, reason} -> {:error, {:refresh_unavailable, reason}}
    end
  end

  defp warn_if_in_transaction(repo, domain) do
    if repo.in_transaction?() do
      Logger.warning(
        "ex_shopify_app: a locked token refresh for #{domain} was requested from inside " <>
          "a caller transaction. The refresh itself runs in a separate supervised " <>
          "process on its own connection, so the caller's transaction can no longer roll " <>
          "it back — but the caller holds a pooled connection while it waits, which can " <>
          "exhaust the pool under concurrency. Move the refresh outside the transaction."
      )
    end

    :ok
  end
end
