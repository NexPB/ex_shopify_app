defmodule ExShopifyApp.ShopTest do
  use ExUnit.Case, async: true

  alias ExShopifyApp.Shop

  doctest Shop

  describe "valid_domain?/1" do
    test "accepts a {shop}.myshopify.com hostname, with or without https://" do
      assert Shop.valid_domain?("acme.myshopify.com")
      assert Shop.valid_domain?("acme-2.myshopify.com")
      assert Shop.valid_domain?("https://acme.myshopify.com")
    end

    test "rejects hosts that only contain or end with .myshopify.com" do
      refute Shop.valid_domain?("acme.myshopify.com.evil.example")
      refute Shop.valid_domain?("evil.example#.myshopify.com")
      refute Shop.valid_domain?("evil.example/.myshopify.com")
      refute Shop.valid_domain?("evil.example?.myshopify.com")
      refute Shop.valid_domain?("user@acme.myshopify.com")
      refute Shop.valid_domain?("acme.myshopify.com\n")
      refute Shop.valid_domain?("-acme.myshopify.com")
      refute Shop.valid_domain?(".myshopify.com")
    end

    test "rejects non-binaries" do
      refute Shop.valid_domain?(nil)
      refute Shop.valid_domain?(%{shopify_domain: "acme.myshopify.com"})
    end
  end

  describe "validate_domain!/1" do
    test "returns the normalized domain" do
      assert Shop.validate_domain!("https://acme.myshopify.com") == "acme.myshopify.com"
    end

    test "raises ArgumentError for any other value" do
      assert_raise ArgumentError, ~r/myshopify\.com domain/, fn ->
        Shop.validate_domain!("evil.example")
      end
    end
  end
end
