defmodule ExShopifyApp.TestingTest do
  use ExUnit.Case, async: true

  import ExShopifyApp.Testing
  import Plug.Test

  alias ExShopifyApp.Plugs.{AdminAuth, AssignShop, ExtensionAuth, Hmac}
  alias Plug.Conn

  doctest ExShopifyApp.Testing

  defmodule WebhookPipeline do
    use Plug.Builder

    plug Plug.Parsers,
      parsers: [:json],
      json_decoder: JSON,
      body_reader: {ExShopifyApp.Web.CacheBodyReader, :read_body, []}

    plug Hmac, scheme: :webhook
    plug AssignShop, type: :header, get_shop_by_domain: &__MODULE__.shop/1

    def shop(shopify_domain), do: %{shopify_domain: shopify_domain}
  end

  @domain "acme.myshopify.com"

  describe "admin_session_token/2" do
    test "passes AdminAuth" do
      conn = :get |> conn("/") |> bearer(admin_session_token(@domain)) |> admin_auth()

      refute conn.halted
      assert ExShopifyApp.Token.Plug.current_resource(conn) == @domain
    end

    test "fails AdminAuth when signed with another secret" do
      conn =
        :get
        |> conn("/")
        |> bearer(admin_session_token(@domain, secret: "other-secret"))
        |> admin_auth()

      assert conn.status == 401
    end

    test "removes a claim set to nil" do
      token = admin_session_token(@domain, claims: %{"iss" => nil})

      assert :get |> conn("/") |> bearer(token) |> admin_auth() |> Map.fetch!(:status) == 401
    end
  end

  describe "extension_session_token/2" do
    test "passes ExtensionAuth" do
      conn =
        :post
        |> conn("/")
        |> bearer(extension_session_token(@domain))
        |> ExtensionAuth.call(ExtensionAuth.init([]))

      refute conn.halted
      assert ExShopifyApp.Token.Plug.current_resource(conn) == @domain
    end

    test "fails AdminAuth, which requires iss" do
      conn = :get |> conn("/") |> bearer(extension_session_token(@domain)) |> admin_auth()

      assert conn.status == 401
    end
  end

  describe "put_session/2" do
    test "lets AssignShop read the shop domain" do
      conn =
        :get
        |> conn("/")
        |> put_session(admin_session_token(@domain))
        |> AssignShop.call(AssignShop.init(get_shop_by_domain: &%{shopify_domain: &1}))

      refute conn.halted
      assert conn.assigns.shopify_domain == @domain
    end
  end

  describe "put_webhook_headers/3" do
    test "passes the Hmac plug and AssignShop through Plug.Parsers" do
      body = JSON.encode!(%{"id" => 1})

      conn =
        :post
        |> conn("/webhooks", body)
        |> put_webhook_headers(body, shopify_domain: @domain, topic: "orders/create")
        |> WebhookPipeline.call([])

      refute conn.halted
      assert conn.assigns.shopify_domain == @domain
      assert conn.body_params == %{"id" => 1}
      assert Conn.get_req_header(conn, "x-shopify-topic") == ["orders/create"]
    end

    test "fails the Hmac plug when signed with another secret" do
      body = JSON.encode!(%{"id" => 1})

      conn =
        :post
        |> conn("/webhooks", body)
        |> put_webhook_headers(body, shopify_domain: @domain, secret: "other-secret")
        |> WebhookPipeline.call([])

      assert conn.status == 401
    end
  end

  describe "app_proxy_query/3" do
    test "signs Shopify's documented example" do
      timestamp = 1_317_327_555

      query =
        app_proxy_query(
          @domain,
          [extra: ["1", "2"], logged_in_customer_id: "", path_prefix: "/apps/awesome_reviews"],
          timestamp: timestamp
        )

      message =
        "extra=1,2logged_in_customer_id=path_prefix=/apps/awesome_reviews" <>
          "shop=acme.myshopify.comtimestamp=#{timestamp}"

      signature =
        :hmac
        |> :crypto.mac(:sha256, ExShopifyApp.api_secret(), message)
        |> Base.encode16(case: :lower)

      assert String.ends_with?(query, "&signature=" <> signature)
    end

    test "passes the Hmac plug and AssignShop with nested params" do
      query = app_proxy_query(@domain, %{"filter" => %{"tag" => "a b"}, "page" => 2})

      conn =
        :get
        |> conn("/proxy?" <> query)
        |> Conn.fetch_query_params()
        |> Hmac.call(Hmac.init(scheme: :app_proxy))
        |> AssignShop.call(
          AssignShop.init(type: :app_proxy, get_shop_by_domain: &%{shopify_domain: &1})
        )

      refute conn.halted
      assert conn.assigns.shopify_domain == @domain
      assert conn.query_params["filter"] == %{"tag" => "a b"}
    end

    test "fails the Hmac plug without a timestamp" do
      conn =
        :get
        |> conn("/proxy?" <> app_proxy_query(@domain, [], timestamp: nil))
        |> Hmac.call(Hmac.init(scheme: :app_proxy))

      assert conn.status == 401
    end
  end

  describe "put_hmac_verified/2" do
    test "lets AssignShop read the shop domain header" do
      conn =
        :post
        |> conn("/webhooks")
        |> put_hmac_verified(:webhook)
        |> Conn.put_req_header("x-shopify-shop-domain", @domain)
        |> AssignShop.call(AssignShop.init(type: :header, get_shop_by_domain: & &1))

      refute conn.halted
      assert conn.assigns.authenticated_shop == @domain
    end

    test "rejects an unknown scheme" do
      assert_raise FunctionClauseError, fn -> put_hmac_verified(conn(:get, "/"), :other) end
    end
  end

  describe "access_token/2" do
    test "builds an expiring token" do
      token = access_token(@domain)

      assert token.shopify_domain == @domain
      assert "shpat_" <> _ = token.access_token
      assert "shprt_" <> _ = token.refresh_token
      assert %DateTime{} = token.expires_at
      assert %DateTime{} = token.refresh_token_expires_at
    end

    test "builds a token that does not expire" do
      token =
        access_token(@domain, %{
          "expires_in" => nil,
          "refresh_token" => nil,
          "refresh_token_expires_in" => nil
        })

      assert token.refresh_token == nil
      assert token.expires_at == nil
      assert token.refresh_token_expires_at == nil
    end
  end

  defp bearer(conn, token), do: Conn.put_req_header(conn, "authorization", "Bearer " <> token)

  defp admin_auth(conn) do
    conn
    |> Conn.fetch_query_params()
    |> AdminAuth.call(AdminAuth.init([]))
  end
end
