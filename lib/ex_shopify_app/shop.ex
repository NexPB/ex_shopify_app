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

  # `%{key: type}` alone allows no other keys, so Dialyzer would reject host structs
  # such as a shop schema; `optional(atom())` keeps each map open.

  @typedoc "A shop reference carrying at least its `:shopify_domain`."
  @type t :: %{required(:shopify_domain) => String.t(), optional(atom()) => any()}

  @typedoc "A shop reference carrying its `:shopify_domain` and offline `:access_token`."
  @type authorized :: %{
          required(:shopify_domain) => String.t(),
          required(:access_token) => String.t(),
          optional(atom()) => any()
        }

  @typedoc "A shop reference carrying its `:shop_gid`, e.g. `\"gid://shopify/Shop/123\"`."
  @type identified :: %{required(:shop_gid) => String.t(), optional(atom()) => any()}

  @doc """
  Normalizes a shop domain the same way `ExShopifyApp.AccessToken.client/1` does:
  strips a leading `https://` so the stored key matches the host used for requests.
  """
  @spec normalize_domain(String.t() | nil) :: String.t() | nil
  def normalize_domain(nil), do: nil

  def normalize_domain(domain) when is_binary(domain) do
    String.trim_leading(domain, "https://")
  end

  @doc """
  Returns `true` when `domain` is a `{shop}.myshopify.com` hostname, with or without a
  leading `https://`.

  ## Examples

      iex> ExShopifyApp.Shop.valid_domain?("acme.myshopify.com")
      true

      iex> ExShopifyApp.Shop.valid_domain?("evil.example#.myshopify.com")
      false

  """
  @spec valid_domain?(term()) :: boolean()
  def valid_domain?(domain) when is_binary(domain) do
    Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9\-]*\.myshopify\.com\z/, normalize_domain(domain))
  end

  def valid_domain?(_domain), do: false

  @doc """
  Returns the normalized `domain` when `valid_domain?/1` accepts it.

  Raises `ArgumentError` for any other value.
  """
  @spec validate_domain!(term()) :: String.t()
  def validate_domain!(domain) do
    if valid_domain?(domain) do
      normalize_domain(domain)
    else
      raise ArgumentError,
            "expected a {shop}.myshopify.com domain, got: #{inspect(domain)}"
    end
  end
end
