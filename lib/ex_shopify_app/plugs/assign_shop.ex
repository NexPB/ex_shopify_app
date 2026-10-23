defmodule ExShopifyApp.Plugs.AssignShop do
  @moduledoc """
  A plug to assign a shop identified by a token or header.

  Responds `401` and halts when no `{shop}.myshopify.com` domain is found.

  ## Options

  - `:get_shop_by_domain` - A function that fetches the Shop resource by domain.
  - `:type` - Can be `:token` or `:header`. Defaults to `:token`. `:header` reads
    `x-shopify-shop-domain` and requires `ExShopifyApp.Plugs.Hmac` with
    `scheme: :webhook` earlier in the pipeline.

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
end
