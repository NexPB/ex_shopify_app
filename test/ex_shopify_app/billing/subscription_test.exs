defmodule ExShopifyApp.Billing.SubscriptionTest do
  use ExUnit.Case, async: true

  import Mox
  import ExShopifyApp.HTTPMockHelpers, only: [expect_http_json: 2]

  alias ExShopifyApp.Billing.Subscription

  setup :verify_on_exit!

  @shop %{shopify_domain: "shop.myshopify.com", access_token: "shpat_123"}

  describe "fetch_active/1" do
    test "returns the first active subscription as a struct" do
      expect_http_json(
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

      assert {:ok,
              %Subscription{
                name: "Pop-up",
                status: "ACTIVE",
                current_period_end: "2026-07-28T00:00:00Z"
              }} = Subscription.fetch_active(@shop)
    end

    test "returns {:error, :no_subscription} when there are no active subscriptions" do
      expect_http_json(
        %{"data" => %{"currentAppInstallation" => %{"activeSubscriptions" => []}}},
        status: 200
      )

      assert Subscription.fetch_active(@shop) == {:error, :no_subscription}
    end

    test "returns {:error, env} on a non-200 API response" do
      expect_http_json(%{"errors" => "nope"}, status: 401)

      assert {:error, %Tesla.Env{status: 401}} = Subscription.fetch_active(@shop)
    end

    test "returns {:error, {:graphql, errors}} when a 200 carries GraphQL errors" do
      expect_http_json(%{"data" => nil, "errors" => [%{"message" => "throttled"}]}, status: 200)

      assert {:error, {:graphql, [%{"message" => "throttled"}]}} =
               Subscription.fetch_active(@shop)
    end
  end
end
