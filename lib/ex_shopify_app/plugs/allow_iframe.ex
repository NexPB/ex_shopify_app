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
    domains = ["https://admin.shopify.com"]

    domains =
      if is_binary(resource) do
        ["https://#{resource}"] ++ domains
      else
        domains
      end

    conn
    |> Plug.Conn.delete_resp_header("x-frame-options")
    |> Conn.put_resp_header(
      "content-security-policy",
      "frame-ancestors #{Enum.join(domains, " ")};"
    )
  end
end
