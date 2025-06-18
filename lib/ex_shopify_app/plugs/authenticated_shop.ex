defmodule ExShopifyApp.Plugs.AssignShop do
  @moduledoc """
  A plug to assign a shop identified by a token or header.

  ## Options

  - `:get_shop_by_domain` - A function that fetches the Shop resource by domain.
  - `:type` - Can be `:token` or `:header`. Defaults to `:token`.

  ## Example

    plug ExShopifyApp.Pipeline.Shop,
      get_shop_by_domain: &MyApp.get_shop_by_domain/1

  """

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
          case Conn.get_req_header(conn, "x-shopify-shop-domain") do
            [shopify_domain] -> shopify_domain
            _ -> nil
          end
      end

    if is_binary(shopify_domain) do
      get_shop = Keyword.fetch!(opts, :get_shop_by_domain)

      conn
      |> Conn.assign(:shopify_domain, shopify_domain)
      |> Conn.assign(:authenticated_shop, get_shop.(shopify_domain))
    else
      conn
      |> Conn.put_status(:unauthorized)
      |> Conn.send_resp(401, "Unauthorized")
    end
  end
end
