defmodule ExShopifyApp.Plugs.AllowIframeTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias ExShopifyApp.Plugs.AllowIframe

  defp csp(conn), do: get_resp_header(conn, "content-security-policy")

  defp call(conn), do: AllowIframe.call(conn, AllowIframe.init([]))

  test "sets frame-ancestors to the Shopify admin" do
    conn =
      conn(:get, "/")
      |> put_resp_header("x-frame-options", "DENY")
      |> call()

    assert csp(conn) == ["frame-ancestors https://admin.shopify.com;"]
    assert get_resp_header(conn, "x-frame-options") == []
  end

  test "adds the shop domain of the current resource" do
    conn =
      conn(:get, "/")
      |> ExShopifyApp.Token.Plug.put_current_resource("shop.myshopify.com")
      |> call()

    assert csp(conn) == [
             "frame-ancestors https://shop.myshopify.com https://admin.shopify.com;"
           ]
  end

  test "keeps the other directives of an existing policy" do
    conn =
      conn(:get, "/")
      |> put_resp_header("content-security-policy", "default-src 'self'; script-src 'self'")
      |> call()

    assert csp(conn) == [
             "default-src 'self'; script-src 'self'; frame-ancestors https://admin.shopify.com;"
           ]
  end

  test "replaces an existing frame-ancestors directive" do
    conn =
      conn(:get, "/")
      |> put_resp_header(
        "content-security-policy",
        "Frame-Ancestors 'none'; img-src *;"
      )
      |> call()

    assert csp(conn) == ["img-src *; frame-ancestors https://admin.shopify.com;"]
  end
end
