defmodule ExShopifyApp.StorefrontTest do
  use ExUnit.Case, async: true

  import Mox
  import ExShopifyApp.HTTPMockHelpers, only: [expect_http_call: 3]

  alias ExShopifyApp.Graphql
  alias ExShopifyApp.Storefront

  setup :verify_on_exit!

  @shop %{shopify_domain: "shop.myshopify.com", access_token: "shpat_123"}
  @cart_query "query($id: ID!) { cart(id: $id) { id } }"
  @cart_variables %{"id" => "gid://shopify/Cart/c1"}

  describe "client/2" do
    test "sends the query to the storefront graphql url with the private token header" do
      expect_http_call(
        fn env ->
          assert env.method == :post
          assert env.url == "https://shop.myshopify.com/api/2026-01/graphql.json"
          assert {"shopify-storefront-private-token", "shpat_123"} in env.headers
          refute List.keymember?(env.headers, "shopify-storefront-buyer-ip", 0)
          refute List.keymember?(env.headers, "x-shopify-access-token", 0)
          assert JSON.decode!(env.body)["query"] == @cart_query
          assert JSON.decode!(env.body)["variables"] == @cart_variables
        end,
        %{"data" => %{"cart" => nil}},
        status: 200
      )

      assert {:ok, %{"cart" => nil}} = run_cart_query(Storefront.client(@shop))
    end

    test "uses the api_version option in the url" do
      expect_http_call(
        fn env ->
          assert env.url == "https://shop.myshopify.com/api/2026-10/graphql.json"
        end,
        %{"data" => %{"cart" => nil}},
        status: 200
      )

      assert {:ok, %{"cart" => nil}} =
               run_cart_query(Storefront.client(@shop, api_version: "2026-10"))
    end

    test "adds the buyer ip header when buyer_ip is given" do
      expect_http_call(
        fn env ->
          assert {"shopify-storefront-buyer-ip", "203.0.113.7"} in env.headers
        end,
        %{"data" => %{"cart" => nil}},
        status: 200
      )

      assert {:ok, %{"cart" => nil}} =
               run_cart_query(Storefront.client(@shop, buyer_ip: "203.0.113.7"))
    end

    test "normalizes a domain given with https://" do
      expect_http_call(
        fn env ->
          assert env.url == "https://shop.myshopify.com/api/2026-01/graphql.json"
        end,
        %{"data" => %{"cart" => nil}},
        status: 200
      )

      assert {:ok, %{"cart" => nil}} =
               run_cart_query(
                 Storefront.client(%{@shop | shopify_domain: "https://shop.myshopify.com"})
               )
    end
  end

  describe "query/3" do
    test "returns {:error, %Tesla.Env{status: 403}} without the client when storefront access is denied" do
      expect_http_call(
        fn _env -> :ok end,
        %{"errors" => [%{"extensions" => %{"code" => "ACCESS_DENIED"}}]},
        status: 403
      )

      assert {:error, %Tesla.Env{status: 403, __client__: nil} = env} =
               run_cart_query(Storefront.client(@shop))

      refute inspect(env, limit: :infinity) =~ "shpat_123"
    end

    test "returns {:error, {:graphql, errors}} on a 200 with errors" do
      errors = [%{"message" => "Variable $id is invalid"}]

      expect_http_call(fn _env -> :ok end, %{"data" => nil, "errors" => errors}, status: 200)

      assert {:error, {:graphql, ^errors}} = run_cart_query(Storefront.client(@shop))
    end

    test "defaults the variables to an empty map" do
      expect_http_call(
        fn env -> assert JSON.decode!(env.body)["variables"] == %{} end,
        %{"data" => %{}},
        status: 200
      )

      assert {:ok, %Tesla.Env{status: 200}} =
               @shop |> Storefront.client() |> Storefront.query("query { __typename }")
    end
  end

  defp run_cart_query(client) do
    client
    |> Storefront.query(@cart_query, @cart_variables)
    |> Graphql.unwrap(&{:ok, &1})
  end
end
