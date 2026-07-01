defmodule ExShopifyApp.Billing.TokenCache do
  @moduledoc """
  Behaviour for a cached Shopify app events access-token source.

  `ExShopifyApp.Billing.AppEvents` resolves the configured implementation via
  `ExShopifyApp.app_events_config/0` and calls `fetch/0` on it. The default
  implementation is `ExShopifyApp.Billing.TokenServer`, a supervised GenServer that
  serializes token refreshes so concurrent first-callers coalesce onto a single token
  fetch. Swap it for your own (e.g. a Cachex/ETS TTL cache with non-blocking reads):

      config :ex_shopify_app, :app_events,
        token_cache: MyApp.TokenCache

  If you supervise your implementation yourself, disable the library's auto-start:

      config :ex_shopify_app, :app_events,
        start_token_cache: false
  """

  @typedoc "A Shopify app events access token."
  @type token :: String.t()

  # `fetch/0` is the required contract — it's what `AppEvents` calls. `fetch/1`
  # (server/name override) is optional, so implementations like `TokenServer`
  # that expose `fetch(server \\ __MODULE__)` satisfy both arities cleanly.
  @callback fetch() :: {:ok, token()} | {:error, any()}
  @callback fetch(GenServer.server()) :: {:ok, token()} | {:error, any()}
  @optional_callbacks fetch: 1
end
