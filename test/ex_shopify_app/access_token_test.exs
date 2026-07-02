defmodule ExShopifyApp.AccessTokenTest do
  use ExUnit.Case, async: true

  import Mox
  import Tesla.Test
  import ExShopifyApp.TestHelpers, only: [json_response: 2]
  import ExShopifyApp.HTTPMockHelpers, only: [expect_http_json: 2]

  alias ExShopifyApp.AccessToken
  alias ExShopifyApp.AccessToken.Token

  setup :verify_on_exit!

  @shop %{shopify_domain: "shop.myshopify.com"}

  @expiring_body %{
    "access_token" => "shpat_123",
    "scope" => "write_orders",
    "expires_in" => 3600,
    "refresh_token" => "shprt_456",
    "refresh_token_expires_in" => 7_776_000
  }

  describe "fetch/3" do
    test "requests an expiring offline token by default and parses the response" do
      expect_tesla_call(
        times: 1,
        returns: fn %{method: :post, url: url, body: body}, _opts ->
          assert url == "https://shop.myshopify.com/admin/oauth/access_token"
          params = JSON.decode!(body)
          assert params["grant_type"] == "urn:ietf:params:oauth:grant-type:token-exchange"

          assert params["requested_token_type"] ==
                   "urn:shopify:params:oauth:token-type:offline-access-token"

          assert params["subject_token"] == "session-token"
          assert params["expiring"] == "1"
          {:ok, json_response(@expiring_body, status: 200)}
        end
      )

      assert {:ok, %Token{} = token} = AccessToken.fetch(@shop, "session-token")
      assert token.access_token == "shpat_123"
      assert token.refresh_token == "shprt_456"
      assert token.shopify_domain == "shop.myshopify.com"
      assert %DateTime{} = token.expires_at
    end

    test "omits the expiring param when expiring: false" do
      expect_tesla_call(
        times: 1,
        returns: fn %{method: :post, body: body}, _opts ->
          refute Map.has_key?(JSON.decode!(body), "expiring")

          {:ok,
           json_response(%{"access_token" => "shpat_x", "scope" => "read_orders"}, status: 200)}
        end
      )

      assert {:ok, %Token{expires_at: nil}} =
               AccessToken.fetch(@shop, "session-token", expiring: false)
    end

    test "requests an online token when type: :online" do
      expect_tesla_call(
        times: 1,
        returns: fn %{method: :post, body: body}, _opts ->
          params = JSON.decode!(body)

          assert params["requested_token_type"] ==
                   "urn:shopify:params:oauth:token-type:online-access-token"

          {:ok, json_response(@expiring_body, status: 200)}
        end
      )

      assert {:ok, %Token{}} = AccessToken.fetch(@shop, "session-token", type: :online)
    end

    test "non-200 returns {:error, env}" do
      expect_http_json(%{"error" => "invalid_subject_token"}, status: 400)

      assert {:error, %Tesla.Env{status: 400}} = AccessToken.fetch(@shop, "session-token")
    end
  end

  describe "refresh/2" do
    test "posts a refresh_token grant and returns a new token" do
      expect_tesla_call(
        times: 1,
        returns: fn %{method: :post, body: body}, _opts ->
          params = JSON.decode!(body)
          assert params["grant_type"] == "refresh_token"
          assert params["refresh_token"] == "shprt_old"
          assert params["client_id"] == "test-api-key"
          {:ok, json_response(%{@expiring_body | "refresh_token" => "shprt_new"}, status: 200)}
        end
      )

      assert {:ok, %Token{} = token} = AccessToken.refresh(@shop, "shprt_old")
      assert token.refresh_token == "shprt_new"
      assert token.shopify_domain == "shop.myshopify.com"
    end

    test "non-200 returns {:error, env}" do
      expect_http_json(%{"error" => "invalid_grant"}, status: 400)

      assert {:error, %Tesla.Env{status: 400}} = AccessToken.refresh(@shop, "shprt_old")
    end
  end

  describe "migrate/2" do
    test "exchanges a non-expiring offline token for an expiring one" do
      expect_tesla_call(
        times: 1,
        returns: fn %{method: :post, url: url, body: body}, _opts ->
          assert url == "https://shop.myshopify.com/admin/oauth/access_token"
          params = JSON.decode!(body)
          assert params["grant_type"] == "urn:ietf:params:oauth:grant-type:token-exchange"

          assert params["subject_token_type"] ==
                   "urn:shopify:params:oauth:token-type:offline-access-token"

          assert params["requested_token_type"] ==
                   "urn:shopify:params:oauth:token-type:offline-access-token"

          assert params["subject_token"] == "shpat_lifetime"
          assert params["expiring"] == "1"
          assert params["client_id"] == "test-api-key"
          {:ok, json_response(@expiring_body, status: 200)}
        end
      )

      assert {:ok, %Token{} = token} = AccessToken.migrate(@shop, "shpat_lifetime")
      assert token.access_token == "shpat_123"
      assert token.refresh_token == "shprt_456"
      assert token.shopify_domain == "shop.myshopify.com"
      assert %DateTime{} = token.expires_at
    end

    test "non-200 returns {:error, env}" do
      expect_http_json(%{"error" => "invalid_subject_token"}, status: 400)

      assert {:error, %Tesla.Env{status: 400}} = AccessToken.migrate(@shop, "shpat_lifetime")
    end
  end
end
