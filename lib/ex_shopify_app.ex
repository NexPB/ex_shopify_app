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
