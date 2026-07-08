defmodule ExShopifyApp.BillingTest do
  use ExUnit.Case, async: true

  alias ExShopifyApp.Billing

  doctest Billing

  describe "pricing_url/2" do
    test "builds the hosted plan-selection page URL from the store handle" do
      assert Billing.pricing_url(%{shopify_domain: "acme.myshopify.com"}, "my-app") ==
               "https://admin.shopify.com/store/acme/charges/my-app/pricing_plans"
    end

    test "normalizes a domain carrying a leading https://" do
      assert Billing.pricing_url(%{shopify_domain: "https://acme.myshopify.com"}, "my-app") ==
               "https://admin.shopify.com/store/acme/charges/my-app/pricing_plans"
    end
  end
end
