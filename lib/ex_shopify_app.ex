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
end
