defmodule ExShopifyApp.AccessToken.Telemetry do
  @moduledoc """
  Telemetry emission for offline access-token refreshes.

  All events share the `[:ex_shopify_app, :access_token, :refresh]` prefix:

    * `[..., :start | :stop | :exception]` — the refresh span.
    * `[..., :persistence_retried]` — Shopify returned a new token but the durable write
      failed, so the refresh runs once more (also logged at `warning`).
    * `[..., :persistence_failed]` — the second run stored no token either (also
      logged at `error`). `:result` classifies the second run.
    * `[..., :stale_while_error]` — a refresh failed but the still-valid old token was
      served.

  Metadata carries `:shopify_domain`, `:refresh_generation`, and a `:result`
  classification — never token values.
  """

  require Logger

  @event [:ex_shopify_app, :access_token, :refresh]

  @doc """
  Emit the refresh `:start` event and return the monotonic start time to pair with
  `refresh_stop/3` or `refresh_exception/4`.
  """
  def refresh_start(meta) do
    start_time = System.monotonic_time()
    :telemetry.execute(@event ++ [:start], %{system_time: System.system_time()}, meta)
    start_time
  end

  @doc "Emit the refresh `:stop` event with the elapsed duration and classified result."
  def refresh_stop(start_time, meta, result) do
    :telemetry.execute(
      @event ++ [:stop],
      %{duration: System.monotonic_time() - start_time},
      Map.put(meta, :result, classify(result))
    )
  end

  @doc "Emit the refresh `:exception` event for a crash in the refresh path."
  def refresh_exception(start_time, meta, exception, stacktrace) do
    :telemetry.execute(
      @event ++ [:exception],
      %{duration: System.monotonic_time() - start_time},
      Map.merge(meta, %{
        kind: :error,
        reason: exception,
        stacktrace: stacktrace
      })
    )
  end

  @doc """
  Emit the event for a failed write after a successful Shopify refresh.

  With `retry: true`, emits `:persistence_retried` and logs a warning. Otherwise emits
  `:persistence_failed` and logs an error; `:retry_result` is the second run's result,
  classified into `:result`.
  """
  def persistence_failed(domain, token, opts \\ []) do
    meta = %{shopify_domain: domain, refresh_generation: token.refresh_generation}

    {event, meta} =
      if Keyword.get(opts, :retry, false) do
        {:persistence_retried, meta}
      else
        result = classify(Keyword.get(opts, :retry_result, {:error, :unknown}))
        {:persistence_failed, Map.put(meta, :result, result)}
      end

    :telemetry.execute(@event ++ [event], %{system_time: System.system_time()}, meta)

    log_lost_write(event, meta)
  end

  defp log_lost_write(:persistence_retried, %{shopify_domain: domain}) do
    Logger.warning(
      "ex_shopify_app: the write after a successful Shopify refresh failed for #{domain}. " <>
        "Refreshing again from the stored token."
    )
  end

  defp log_lost_write(:persistence_failed, %{shopify_domain: domain, result: result}) do
    Logger.error(
      "ex_shopify_app: the write after a successful Shopify refresh failed for #{domain}, " <>
        "and the retry stored no token (#{result}). The call returns the newest token " <>
        "Shopify issued in a PersistenceFailure."
    )
  end

  @doc "Emit the `:stale_while_error` event when the old token is served after a failed refresh."
  def stale_while_error(token, reason) do
    :telemetry.execute(
      @event ++ [:stale_while_error],
      %{system_time: System.system_time()},
      %{
        shopify_domain: token.shopify_domain,
        refresh_generation: token.refresh_generation,
        result: classify({:error, reason})
      }
    )
  end

  defp classify({:ok, _}), do: :ok
  defp classify({:error, :no_token}), do: :no_token
  defp classify({:error, :reauthorization_required}), do: :reauthorization_required
  defp classify({:error, {:refresh_failed, _}}), do: :refresh_failed
  defp classify({:error, {:token_persistence_failed_after_refresh, _}}), do: :persistence_failed
  defp classify({:error, {:lock_timeout, _}}), do: :lock_timeout
  defp classify({:error, {:refresh_crashed, _}}), do: :refresh_crashed
  defp classify({:error, {:refresh_unavailable, _}}), do: :refresh_unavailable
  defp classify({:error, _}), do: :error
end
