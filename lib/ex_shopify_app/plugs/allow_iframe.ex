defmodule ExShopifyApp.Plugs.AllowIframe do
  @moduledoc """
  A plug to allow iframe requests from the Shopify admin.
  """

  alias ExShopifyApp.Token
  alias Plug.Conn

  def init(opts) do
    opts
  end

  def call(%Conn{} = conn, _opts) do
    resource = Token.Plug.current_resource(conn)

    if is_binary(resource) do
      Conn.put_resp_header(
        conn,
        "Content-Security-Policy",
        "frame-ancestors https://#{resource} https://admin.shopify.com;"
      )
    else
      conn
    end
  end
end
