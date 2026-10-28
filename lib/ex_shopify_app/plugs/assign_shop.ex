defmodule ExShopifyApp.Plugs.AssignShop do
  @moduledoc """
  A plug to assign a shop identified by a token or header.

  Responds `401` and halts when no `{shop}.myshopify.com` domain is found.

  ## Options

  - `:get_shop_by_domain` - A function that fetches the Shop resource by domain.
  - `:type` - Where to read the shop domain. Defaults to `:token`.
    - `:token` - the session token verified by `ExShopifyApp.Plugs.Token` or
      `ExShopifyApp.Plugs.ExtensionToken`.
    - `:header` - the `x-shopify-shop-domain` header. Requires `ExShopifyApp.Plugs.Hmac`
      with `scheme: :webhook` earlier in the pipeline.
    - `:app_proxy` - the `shop` query parameter. Requires `ExShopifyApp.Plugs.Hmac` with
      `scheme: :app_proxy` earlier in the pipeline.
    - `:flow_action` - the `shopify_domain` body parameter of a Shopify Flow action.
      Requires `Plug.Parsers` and `ExShopifyApp.Plugs.Hmac` with `scheme: :webhook`
      earlier in the pipeline.

  ## Example

    plug ExShopifyApp.Pipeline.Shop,
      get_shop_by_domain: &MyApp.get_shop_by_domain/1

  """

  alias ExShopifyApp.Shop
  alias ExShopifyApp.Token
  alias Plug.Conn

  def init(opts) do
    unless Keyword.has_key?(opts, :get_shop_by_domain) do
      raise ArgumentError, "Plug requires a :get_shop_by_domain function in options"
    end

    opts
  end

  def call(%Conn{} = conn, opts) do
    shopify_domain =
      case Keyword.get(opts, :type, :token) do
        :token ->
          Token.Plug.current_resource(conn)

        :header ->
          # Shopify's webhook HMAC does not cover this header: a verified body rejects
          # forged requests, not a replayed body sent with a different header.
          with :webhook <- conn.private[:ex_shopify_app_hmac],
               [shopify_domain] <- Conn.get_req_header(conn, "x-shopify-shop-domain") do
            shopify_domain
          else
            _ -> nil
          end

        :app_proxy ->
          with :app_proxy <- conn.private[:ex_shopify_app_hmac],
               {:ok, shopify_domain} <- fetch_query_param(conn, "shop") do
            shopify_domain
          else
            _ -> nil
          end

        :flow_action ->
          with :webhook <- conn.private[:ex_shopify_app_hmac],
               %{"shopify_domain" => shopify_domain} <- conn.body_params do
            shopify_domain
          else
            _ -> nil
          end
      end

    if Shop.valid_domain?(shopify_domain) do
      get_shop = Keyword.fetch!(opts, :get_shop_by_domain)

      conn
      |> Conn.assign(:shopify_domain, shopify_domain)
      |> Conn.assign(:authenticated_shop, get_shop.(shopify_domain))
    else
      conn
      |> Conn.put_status(:unauthorized)
      |> Conn.send_resp(401, "Unauthorized")
      |> Conn.halt()
    end
  end

  # The Hmac plug signs the raw query, so read it rather than `query_params`, which
  # keeps only the last value of a repeated key. A repeated key returns `:error`.
  defp fetch_query_param(%Conn{} = conn, key) do
    conn.query_string
    |> URI.query_decoder()
    |> Enum.filter(&(elem(&1, 0) == key))
    |> case do
      [{^key, value}] -> {:ok, value}
      _ -> :error
    end
  end
end
