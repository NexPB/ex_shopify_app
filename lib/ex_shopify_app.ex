defmodule ExShopifyApp do
  @moduledoc """
  Documentation for `ExShopifyApp`.
  """

  @spec api_key() :: String.t()
  def api_key() do
    Application.get_env(:ex_shopify_app, :api_key) || System.get_env("SHOPIFY_API_KEY") ||
      raise "Missing config or environment variable: :api_key"
  end

  @spec api_secret() :: String.t()
  def api_secret() do
    Application.get_env(:ex_shopify_app, :api_secret) || System.get_env("SHOPIFY_API_SECRET") ||
      raise "Missing config or environment variable: :api_secret"
  end

  @spec api_version() :: String.t()
  def api_version() do
    Application.get_env(:ex_shopify_app, :api_version, "2026-01")
  end

  @doc """
  Returns the App Events config, with defaults merged in.

  Read individual settings off the result:

    * `:token_cache` — the `ExShopifyApp.Billing.TokenCache` implementation
      `ExShopifyApp.Billing.AppEvents` calls `fetch/0` on. Defaults to
      `ExShopifyApp.Billing.TokenServer`.
    * `:start_token_cache` — whether `ExShopifyApp.Application` auto-supervises the
      `:token_cache` module. Defaults to `true`; set `false` to supervise it yourself.

  Configure via:

      config :ex_shopify_app, :app_events,
        token_cache: MyApp.TokenCache
  """
  @spec app_events_config() :: keyword()
  def app_events_config() do
    conf = Application.get_env(:ex_shopify_app, :app_events, [])

    Keyword.merge(
      [
        token_cache: ExShopifyApp.Billing.TokenServer,
        start_token_cache: true
      ],
      conf
    )
  end

  @doc """
  Returns the Tesla adapter used for all outbound HTTP requests.

  Resolution order:

    1. `:ex_shopify_app, :tesla_adapter` — the library's own config, so host apps can
       set the adapter for this library without touching global Tesla config.
    2. `:tesla, :adapter` — Tesla's global config, honoured as a fallback.
    3. `Tesla.Adapter.Mint` — the default.

  The test env routes everything through `Tesla.Mock` via the global Tesla config.
  """
  @spec tesla_adapter() :: Tesla.Client.adapter()
  def tesla_adapter() do
    Application.get_env(:ex_shopify_app, :tesla_adapter) ||
      Application.get_env(:tesla, :adapter, Tesla.Adapter.Mint)
  end
end
