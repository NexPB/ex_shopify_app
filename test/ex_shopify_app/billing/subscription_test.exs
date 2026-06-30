defmodule ExShopifyApp.Billing.SubscriptionTest do
  use ExUnit.Case, async: true

  import Tesla.Mock, only: [mock: 1]
  import ExShopifyApp.TestHelpers, only: [json_response: 2]

  alias ExShopifyApp.Billing.Subscription

  @shop %{shopify_domain: "shop.myshopify.com", access_token: "shpat_123"}

  describe "fetch_active/1" do
    test "returns the first active subscription as a struct" do
      mock(fn _ ->
        json_response(
          %{
            "data" => %{
              "currentAppInstallation" => %{
                "activeSubscriptions" => [
                  %{
                    "name" => "Pop-up",
                    "status" => "ACTIVE",
                    "currentPeriodEnd" => "2026-07-28T00:00:00Z"
                  }
                ]
              }
            }
          },
          status: 200
        )
      end)

      assert {:ok,
              %Subscription{
                name: "Pop-up",
                status: "ACTIVE",
                current_period_end: "2026-07-28T00:00:00Z"
              }} = Subscription.fetch_active(@shop)
    end

    test "returns {:error, :no_access_token} when there is no usable token (no network call)" do
      assert Subscription.fetch_active(%{@shop | access_token: nil}) == {:error, :no_access_token}
    end

    test "returns {:error, :no_subscription} when there are no active subscriptions" do
      mock(fn _ ->
        json_response(
          %{"data" => %{"currentAppInstallation" => %{"activeSubscriptions" => []}}},
          status: 200
        )
      end)

      assert Subscription.fetch_active(@shop) == {:error, :no_subscription}
    end

    test "returns {:error, env} on a non-200 API response" do
      mock(fn _ -> json_response(%{"errors" => "nope"}, status: 401) end)

      assert {:error, %Tesla.Env{status: 401}} = Subscription.fetch_active(@shop)
    end

    test "returns {:error, {:graphql, errors}} when a 200 carries GraphQL errors" do
      mock(fn _ ->
        json_response(%{"data" => nil, "errors" => [%{"message" => "throttled"}]}, status: 200)
      end)

      assert {:error, {:graphql, [%{"message" => "throttled"}]}} =
               Subscription.fetch_active(@shop)
    end
  end
end
