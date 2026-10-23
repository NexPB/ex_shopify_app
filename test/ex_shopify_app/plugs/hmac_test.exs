defmodule ExShopifyApp.Plugs.HmacTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias ExShopifyApp.Plugs.Hmac
  alias Plug.Conn

  @body ~s({"id":1})

  describe "init/1" do
    test "requires a known :scheme" do
      assert_raise ArgumentError, ~r/:scheme/, fn -> Hmac.init([]) end
      assert_raise ArgumentError, ~r/:scheme/, fn -> Hmac.init(scheme: :any) end
    end
  end

  describe "scheme: :webhook" do
    test "accepts a body signed in the x-shopify-hmac-sha256 header" do
      conn = :post |> webhook_conn(@body, webhook_signature(@body)) |> run(scheme: :webhook)

      refute conn.halted
      assert conn.private.ex_shopify_app_hmac == :webhook
    end

    test "rejects a body the header does not sign" do
      conn =
        :post
        |> webhook_conn(~s({"id":2}), webhook_signature(@body))
        |> run(scheme: :webhook)

      assert_unauthorized(conn)
    end

    test "rejects a repeated header" do
      signature = webhook_signature(@body)
      conn = webhook_conn(:post, @body, signature)

      conn = %{conn | req_headers: [{"x-shopify-hmac-sha256", signature} | conn.req_headers]}

      assert_unauthorized(run(conn, scheme: :webhook))
    end

    test "rejects a valid app proxy signature" do
      timestamp = now()
      message = "shop=acme.myshopify.comtimestamp=#{timestamp}"
      query = "shop=acme.myshopify.com&timestamp=#{timestamp}&signature=#{hex_hmac(message)}"

      conn =
        conn(:post, "/webhooks?" <> query, @body)
        |> Conn.assign(:raw_body, [@body])
        |> run(scheme: :webhook)

      assert_unauthorized(conn)
    end
  end

  describe "scheme: :app_proxy" do
    test "accepts a query signed the way Shopify signs it" do
      conn = :get |> conn("/proxy?" <> app_proxy_query(now())) |> run(scheme: :app_proxy)

      refute conn.halted
      assert conn.private.ex_shopify_app_hmac == :app_proxy
    end

    test "rejects a tampered parameter" do
      query = String.replace(app_proxy_query(now()), "shop=acme", "shop=other")

      assert_unauthorized(:get |> conn("/proxy?" <> query) |> run(scheme: :app_proxy))
    end

    test "rejects a timestamp older than :max_age" do
      query = app_proxy_query(now() - 301)

      assert_unauthorized(:get |> conn("/proxy?" <> query) |> run(scheme: :app_proxy))
    end

    test "rejects a timestamp further than :max_age in the future" do
      query = app_proxy_query(now() + 301)

      assert_unauthorized(:get |> conn("/proxy?" <> query) |> run(scheme: :app_proxy))
    end

    test "honours :max_age" do
      query = app_proxy_query(now() - 600)
      conn = :get |> conn("/proxy?" <> query) |> run(scheme: :app_proxy, max_age: 900)

      refute conn.halted
    end

    test "rejects a signed query without a timestamp" do
      query = "shop=acme.myshopify.com&signature=" <> hex_hmac("shop=acme.myshopify.com")

      assert_unauthorized(:get |> conn("/proxy?" <> query) |> run(scheme: :app_proxy))
    end

    test "rejects a valid webhook header" do
      conn = :post |> webhook_conn(@body, webhook_signature(@body)) |> run(scheme: :app_proxy)

      assert_unauthorized(conn)
    end
  end

  # Plug.Parsers fills `params` before this plug in a real pipeline.
  defp run(conn, opts), do: conn |> Conn.fetch_query_params() |> Hmac.call(Hmac.init(opts))

  defp webhook_conn(method, body, signature) do
    method
    |> conn("/webhooks", body)
    |> Conn.put_req_header("x-shopify-hmac-sha256", signature)
    |> Conn.assign(:raw_body, [body])
  end

  defp webhook_signature(body), do: Base.encode64(hmac(body))

  # The query and message from Shopify's "Authenticate app proxies" example.
  defp app_proxy_query(timestamp) do
    signature =
      hex_hmac(
        "extra=1,2logged_in_customer_id=path_prefix=/apps/awesome_reviews" <>
          "shop=acme.myshopify.comtimestamp=#{timestamp}"
      )

    "extra=1&extra=2&shop=acme.myshopify.com&logged_in_customer_id=" <>
      "&path_prefix=%2Fapps%2Fawesome_reviews&timestamp=#{timestamp}&signature=#{signature}"
  end

  defp hex_hmac(message), do: message |> hmac() |> Base.encode16(case: :lower)

  defp hmac(message), do: :crypto.mac(:hmac, :sha256, ExShopifyApp.api_secret(), message)

  defp now, do: System.system_time(:second)

  defp assert_unauthorized(conn) do
    assert conn.halted
    assert conn.status == 401
    refute Map.has_key?(conn.private, :ex_shopify_app_hmac)
  end
end
