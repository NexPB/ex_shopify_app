defmodule ExShopifyApp.Storefront do
  @moduledoc """
  A minimal Shopify Storefront GraphQL client for server-side requests.

  The client is authenticated with a shop's `shopify_domain` and offline
  `access_token` (an `ExShopifyApp.Shop.authorized/0` reference), sent as a private
  Storefront access token in the `Shopify-Storefront-Private-Token` header.

  The app must hold the `unauthenticated_*` access scopes that the queries need (for
  example `unauthenticated_read_product_listings`), otherwise Shopify answers
  `403 ACCESS_DENIED`. Request them in the app's access scopes and have the merchant
  approve them.

  Unwrap results with `ExShopifyApp.Graphql.unwrap/2`.

  Docs:

    * <https://shopify.dev/docs/api/storefront#authentication>
    * <https://shopify.dev/docs/apps/build/authentication-authorization/app-installation/manage-access-scopes>
  """

  alias ExShopifyApp.Shop

  @doc """
  Returns an authenticated Tesla client for the Shopify Storefront GraphQL API.

  ## Options

    * `:api_version` - the Shopify API version, defaults to
      `ExShopifyApp.api_version/0`.
    * `:buyer_ip` - the buyer's IP address, sent as `Shopify-Storefront-Buyer-IP`.
      Omitted when not given.
    * `:debug` - when `true`, logs requests/responses. Defaults to `false`.
  """
  @spec client(Shop.authorized(), keyword()) :: Tesla.Client.t()
  def client(shop, opts \\ [])

  def client(%{shopify_domain: shopify_domain, access_token: access_token}, opts) do
    api_version = Keyword.get(opts, :api_version, ExShopifyApp.api_version())
    buyer_ip = Keyword.get(opts, :buyer_ip)
    debug? = Keyword.get(opts, :debug, false)

    api_url =
      shopify_domain
      |> api_uri(api_version)
      |> URI.to_string()

    headers = [{"shopify-storefront-private-token", access_token}]

    headers =
      if buyer_ip,
        do: [{"shopify-storefront-buyer-ip", buyer_ip} | headers],
        else: headers

    middleware =
      [
        {Tesla.Middleware.BaseUrl, api_url},
        {Tesla.Middleware.Headers, headers},
        {Tesla.Middleware.JSON, engine: JSON}
      ]

    middleware =
      if debug?,
        do: [{Tesla.Middleware.Logger, []} | middleware],
        else: middleware

    Tesla.client(middleware, ExShopifyApp.tesla_adapter())
  end

  @doc """
  Sends a GraphQL request to the Shopify Storefront API.

  Returns:

    * `{:ok, %Tesla.Env{}}` - the raw response, to be passed to
      `ExShopifyApp.Graphql.unwrap/2`.
    * `{:error, reason}` - a transport error.
  """
  @spec query(Tesla.Client.t(), String.t()) :: Tesla.Env.result()
  @spec query(Tesla.Client.t(), String.t(), map()) :: Tesla.Env.result()
  def query(%Tesla.Client{} = client, query_string, %{} = variables \\ %{}) do
    Tesla.post(client, "/graphql.json", %{
      query: query_string,
      variables: variables
    })
  end

  @spec api_uri(String.t(), String.t()) :: URI.t()
  defp api_uri(shopify_domain, api_version) do
    %URI{
      scheme: "https",
      host: Shop.normalize_domain(shopify_domain),
      path: "/api/#{api_version}"
    }
  end
end
