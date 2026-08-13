defmodule ExShopifyApp.AccessToken.Refresher do
  @moduledoc """
  Runs a locked token mutation in a supervised process, detached from its caller.

  Refreshing rotates both tokens: Shopify invalidates the previous refresh token the
  moment it answers, so the transaction that persists the new one *must* commit. A token
  that is exchanged and then rolled away is lost for good and the merchant has to
  reauthorize. Running that transaction in the caller's process leaves two ways to reach
  exactly that outcome:

    * the caller is already inside its own `Repo.transaction/2`. Ecto checks connections
      out per process, so the refresh becomes a *nested* transaction — it never commits on
      its own, and the caller rolling back afterwards discards the freshly persisted
      token. `SET LOCAL lock_timeout` and the `FOR UPDATE` row lock leak into the caller's
      transaction for the same reason.
    * the caller is killed mid-refresh — a job runner's timeout, `Task.async_stream`'s
      `:timeout`, a supervisor shutdown — taking its connection and the open transaction
      down with it, inside the window between Shopify's response and the commit.

  Running the mutation under `ExShopifyApp.AccessToken.TaskSupervisor` closes both. The
  task holds its own connection, so its transaction is top-level and commits on its own,
  and `Task.Supervisor.async_nolink/2` leaves it unlinked, so the caller's death cannot
  abort it.

  The task is deliberately never `Task.shutdown/2`-ed: abandoning the wait leaves it
  running to completion, because its commit is the thing worth protecting.

  ## Waiting

  Callers wait for the result indefinitely, which matches how long the work took when it
  ran inline; the transaction's own `:timeout` remains the bound on it.
  """

  require Logger

  @supervisor ExShopifyApp.AccessToken.TaskSupervisor

  @doc """
  Run `fun` under `ExShopifyApp.AccessToken.TaskSupervisor` and wait for its result.

  Returns whatever `fun` returns, or `{:error, {:refresh_unavailable, reason}}` if the
  task exits abnormally.

  Logs a warning when `repo` is already in a transaction on the calling process; see the
  module documentation.
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
