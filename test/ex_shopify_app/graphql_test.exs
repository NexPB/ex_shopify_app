defmodule ExShopifyApp.GraphqlTest do
  use ExUnit.Case, async: true

  import Tesla.Mock, only: [mock: 1]
  import ExShopifyApp.TestHelpers, only: [json_response: 2]

  alias ExShopifyApp.Graphql

  doctest Graphql

  @shop %{shopify_domain: "shop.myshopify.com", access_token: "shpat_123"}

  describe "client/2 + query/3" do
    test "posts the query and variables to the Admin GraphQL endpoint" do
      mock(fn env ->
        assert env.method == :post
        assert env.url == "https://shop.myshopify.com/admin/api/2026-01/graphql.json"
        assert {"x-shopify-access-token", "shpat_123"} in env.headers

        params = JSON.decode!(env.body)
        assert params["query"] =~ "currentAppInstallation"
        assert params["variables"] == %{"id" => "gid://shopify/Shop/1"}

        json_response(%{"data" => %{"ok" => true}}, status: 200)
      end)

      assert {:ok, %Tesla.Env{status: 200, body: body}} =
               @shop
               |> Graphql.client()
               |> Graphql.query("query { currentAppInstallation { id } }", %{
                 "id" => "gid://shopify/Shop/1"
               })

      assert body == %{"data" => %{"ok" => true}}
    end

    test "honours the :api_version option" do
      mock(fn env ->
        assert env.url == "https://shop.myshopify.com/admin/api/2025-01/graphql.json"
        json_response(%{"data" => %{}}, status: 200)
      end)

      assert {:ok, %Tesla.Env{status: 200}} =
               @shop
               |> Graphql.client(api_version: "2025-01")
               |> Graphql.query("query { __typename }")
    end

    test "normalizes a domain carrying a leading https://" do
      mock(fn env ->
        assert env.url == "https://shop.myshopify.com/admin/api/2026-01/graphql.json"
        json_response(%{"data" => %{}}, status: 200)
      end)

      assert {:ok, %Tesla.Env{status: 200}} =
               %{@shop | shopify_domain: "https://shop.myshopify.com"}
               |> Graphql.client()
               |> Graphql.query("query { __typename }")
    end
  end

  describe "unwrap/2" do
    test "passes the response data to the callback on a clean 200" do
      result = {:ok, %Tesla.Env{status: 200, body: %{"data" => %{"shop" => "acme"}}}}

      assert {:ok, "acme"} =
               Graphql.unwrap(result, fn data -> {:ok, Map.get(data, "shop")} end)
    end

    test "returns {:error, {:graphql, errors}} on a 200 carrying errors" do
      errors = [%{"message" => "boom"}]
      result = {:ok, %Tesla.Env{status: 200, body: %{"data" => nil, "errors" => errors}}}

      assert {:error, {:graphql, ^errors}} =
               Graphql.unwrap(result, fn _data -> {:ok, :unreached} end)
    end

    test "returns {:error, env} on a non-200 response" do
      result = {:ok, %Tesla.Env{status: 401, body: %{}}}

      assert {:error, %Tesla.Env{status: 401}} =
               Graphql.unwrap(result, fn _data -> {:ok, :unreached} end)
    end
  end
end
