defmodule ExShopifyApp.Plugs.AssignShopTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias ExShopifyApp.Plugs.AssignShop
  alias Plug.Conn

  describe "type: :header" do
    test "assigns the shop of a verified webhook" do
      conn =
        :post
        |> conn("/webhooks")
        |> Conn.put_private(:ex_shopify_app_hmac, :webhook)
        |> Conn.put_req_header("x-shopify-shop-domain", "acme.myshopify.com")
        |> run(type: :header)

      refute conn.halted
      assert conn.assigns.shopify_domain == "acme.myshopify.com"
      assert conn.assigns.authenticated_shop == %{shopify_domain: "acme.myshopify.com"}
    end

    test "rejects a request the Hmac plug did not verify" do
      conn =
        :post
        |> conn("/webhooks")
        |> Conn.put_req_header("x-shopify-shop-domain", "acme.myshopify.com")
        |> run(type: :header)

      assert_unauthorized(conn)
    end

    test "rejects an app proxy request" do
      conn =
        :post
        |> conn("/proxy")
        |> Conn.put_private(:ex_shopify_app_hmac, :app_proxy)
        |> Conn.put_req_header("x-shopify-shop-domain", "acme.myshopify.com")
        |> run(type: :header)

      assert_unauthorized(conn)
    end

    test "rejects a domain other than {shop}.myshopify.com" do
      conn =
        :post
        |> conn("/webhooks")
        |> Conn.put_private(:ex_shopify_app_hmac, :webhook)
        |> Conn.put_req_header("x-shopify-shop-domain", "evil.example#.myshopify.com")
        |> run(type: :header)

      assert_unauthorized(conn)
    end
  end

  describe "type: :app_proxy" do
    test "assigns the shop of a verified app proxy request" do
      conn =
        :get
        |> conn("/proxy?shop=acme.myshopify.com&timestamp=1")
        |> Conn.put_private(:ex_shopify_app_hmac, :app_proxy)
        |> run(type: :app_proxy)

      refute conn.halted
      assert conn.assigns.shopify_domain == "acme.myshopify.com"
    end

    test "rejects a webhook" do
      conn =
        :get
        |> conn("/proxy?shop=acme.myshopify.com")
        |> Conn.put_private(:ex_shopify_app_hmac, :webhook)
        |> run(type: :app_proxy)

      assert_unauthorized(conn)
    end

    test "rejects a repeated shop parameter" do
      conn =
        :get
        |> conn("/proxy?shop=acme.myshopify.com&shop=other.myshopify.com")
        |> Conn.put_private(:ex_shopify_app_hmac, :app_proxy)
        |> run(type: :app_proxy)

      assert_unauthorized(conn)
    end
  end

  describe "type: :flow_action" do
    test "assigns the shop of a verified Flow action" do
      conn =
        :post
        |> conn("/flow", %{"shopify_domain" => "acme.myshopify.com", "handle" => "notify"})
        |> Conn.put_private(:ex_shopify_app_hmac, :webhook)
        |> run(type: :flow_action)

      refute conn.halted
      assert conn.assigns.shopify_domain == "acme.myshopify.com"
    end

    test "rejects a request the Hmac plug did not verify as a webhook" do
      for scheme <- [nil, :app_proxy] do
        conn =
          :post
          |> conn("/flow", %{"shopify_domain" => "acme.myshopify.com"})
          |> Conn.put_private(:ex_shopify_app_hmac, scheme)
          |> run(type: :flow_action)

        assert_unauthorized(conn)
      end
    end

    test "rejects a body without shopify_domain" do
      conn =
        :post
        |> conn("/flow", %{"shop_id" => 1})
        |> Conn.put_private(:ex_shopify_app_hmac, :webhook)
        |> run(type: :flow_action)

      assert_unauthorized(conn)
    end
  end

  describe "type: :token" do
    test "assigns the shop of the session token" do
      conn =
        :get
        |> conn("/")
        |> ExShopifyApp.Token.Plug.put_current_resource("acme.myshopify.com")
        |> run([])

      refute conn.halted
      assert conn.assigns.shopify_domain == "acme.myshopify.com"
    end

    test "rejects a request without a session token" do
      assert_unauthorized(:get |> conn("/") |> run([]))
    end
  end

  defp run(conn, opts) do
    opts = AssignShop.init([get_shop_by_domain: &%{shopify_domain: &1}] ++ opts)
    AssignShop.call(conn, opts)
  end

  defp assert_unauthorized(conn) do
    assert conn.halted
    assert conn.status == 401
    refute Map.has_key?(conn.assigns, :authenticated_shop)
  end
end
