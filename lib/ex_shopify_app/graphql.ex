defmodule ExShopifyApp.Graphql do
  @moduledoc """
  A minimal Shopify Admin GraphQL client, plus GID helpers.

  The client is authenticated with a shop's `shopify_domain` and offline
  `access_token` (an `ExShopifyApp.Shop.authorized/0` reference). The
  `ExShopifyApp.AccessToken.Token` struct already carries both fields, so it can be
  passed directly; any map/struct exposing `:shopify_domain` and `:access_token`
  works too.

  Docs: <https://shopify.dev/docs/api/admin-graphql>
  """

  alias ExShopifyApp.HTTP
  alias ExShopifyApp.Shop

  @doc """
  Returns an authenticated Tesla client for the Shopify Admin GraphQL API.

  ## Options

    * `:api_version` - the Shopify API version, defaults to
      `ExShopifyApp.api_version/0`.
    * `:debug` - when `true`, logs requests/responses. Defaults to `false`.
  """
  @spec client(Shop.authorized(), keyword()) :: Tesla.Client.t()
  def client(shop, opts \\ [])

  def client(%{shopify_domain: shopify_domain, access_token: access_token}, opts) do
    api_version = Keyword.get(opts, :api_version, ExShopifyApp.api_version())
    debug? = Keyword.get(opts, :debug, false)

    api_url =
      shopify_domain
      |> api_uri(api_version)
      |> URI.to_string()

    middleware =
      [
        {Tesla.Middleware.BaseUrl, api_url},
        {Tesla.Middleware.Headers, [{"x-shopify-access-token", access_token}]},
        {Tesla.Middleware.JSON, engine: JSON}
      ]

    middleware =
      if debug?,
        do: [{Tesla.Middleware.Logger, []} | middleware],
        else: middleware

    Tesla.client(middleware, ExShopifyApp.tesla_adapter())
  end

  @doc """
  Sends a GraphQL request to the Shopify Admin API.
  """
  @spec query(Tesla.Client.t(), String.t()) :: Tesla.Env.result()
  @spec query(Tesla.Client.t(), String.t(), map()) :: Tesla.Env.result()
  def query(%Tesla.Client{} = client, query_string, %{} = variables \\ %{}) do
    Tesla.post(client, "/graphql.json", %{
      query: query_string,
      variables: variables
    })
  end

  @doc """
  Unwraps a `query/3` result, surfacing transport, HTTP, and GraphQL errors.

  On a `200` response, a non-empty top-level `"errors"` array yields
  `{:error, {:graphql, errors}}`; otherwise the response's `"data"` map is passed to
  `fun`, which returns the final `{:ok, term} | {:error, term}`. Non-200 responses
  collapse to `{:error, %Tesla.Env{}}` and transport errors to `{:error, reason}`.
  """
  @spec unwrap(Tesla.Env.result(), (map() | nil -> result)) :: result
        when result: {:ok, term()} | {:error, term()}
  def unwrap(result, fun) when is_function(fun, 1) do
    HTTP.unwrap_response(result, fn
      %Tesla.Env{body: %{"errors" => [_ | _] = errors}} -> {:error, {:graphql, errors}}
      %Tesla.Env{body: body} -> fun.(Map.get(body, "data"))
    end)
  end

  @doc """
  Returns the base URI for the Shopify Admin API.
  """
  @spec api_uri(String.t(), String.t()) :: URI.t()
  def api_uri(shopify_domain, api_version) do
    shopify_domain = Shop.normalize_domain(shopify_domain)

    %URI{
      scheme: "https",
      host: shopify_domain,
      path: "/admin/api/#{api_version}"
    }
  end

  @doc """
  Converts a Shopify GID to its trailing integer id.

  ## Examples

      iex> ExShopifyApp.Graphql.trim_gid("gid://shopify/Shop/1")
      1

  """
  @spec trim_gid(String.t()) :: pos_integer()
  def trim_gid("gid://shopify" <> _ = gid) do
    gid
    |> String.split("/")
    |> List.last()
    |> String.to_integer()
  end

  @doc """
  Ensures the given id is a valid Shopify GID for `resource`.

  Already-formed GIDs are returned unchanged.

  ## Examples

      iex> ExShopifyApp.Graphql.ensure_gid(1, "shop")
      "gid://shopify/Shop/1"

      iex> ExShopifyApp.Graphql.ensure_gid("gid://shopify/Shop/1", "shop")
      "gid://shopify/Shop/1"

  """
  @spec ensure_gid(integer() | binary(), binary()) :: binary()
  def ensure_gid(gid, resource) when is_integer(gid) do
    ensure_gid(to_string(gid), resource)
  end

  def ensure_gid(gid, resource) when is_binary(gid) do
    if String.starts_with?(gid, "gid://shopify") do
      gid
    else
      "gid://shopify/#{Macro.camelize(resource)}/#{gid}"
    end
  end
end
