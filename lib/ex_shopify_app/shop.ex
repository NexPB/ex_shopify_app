defmodule ExShopifyApp.Shop do
  @moduledoc """
  Shop references and shop-domain helpers shared across the library.

  A few shapes of shop reference recur throughout the API:

    * `t/0` — a shop identified by its `:shopify_domain` only. Enough to look up,
      refresh, or migrate a stored access token.
    * `authorized/0` — a shop carrying both its `:shopify_domain` and an offline
      `:access_token`, ready to authenticate Admin API requests. The
      `ExShopifyApp.AccessToken.Token` struct satisfies this shape, so it can be passed
      directly; any map exposing both fields works too.
    * `identified/0` — a shop carrying its `:shop_gid`, the shape Shopify's
      shop-global APIs (e.g. App Events) address shops by. See
      `ExShopifyApp.Graphql.ensure_gid/2` for building one from a numeric ID.
  """

  @typedoc "A shop reference carrying at least its `:shopify_domain`."
  @type t :: %{shopify_domain: String.t()}

  @typedoc "A shop reference carrying its `:shopify_domain` and offline `:access_token`."
  @type authorized :: %{shopify_domain: String.t(), access_token: String.t()}

  @typedoc "A shop reference carrying its `:shop_gid`, e.g. `\"gid://shopify/Shop/123\"`."
  @type identified :: %{shop_gid: String.t()}

  @doc """
  Normalizes a shop domain the same way `ExShopifyApp.AccessToken.client/1` does:
  strips a leading `https://` so the stored key matches the host used for requests.
  """
  @spec normalize_domain(String.t() | nil) :: String.t() | nil
  def normalize_domain(nil), do: nil

  def normalize_domain(domain) when is_binary(domain) do
    String.trim_leading(domain, "https://")
  end
end
