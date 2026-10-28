defmodule ExShopifyApp.ShopTest do
  use ExUnit.Case, async: true

  alias ExShopifyApp.Shop

  doctest Shop

  describe "valid_domain?/1" do
    test "accepts a {shop}.myshopify.com hostname, with or without https://" do
      for domain <- [
            "acme.myshopify.com",
            "acme-2.myshopify.com",
            "https://acme.myshopify.com"
          ] do
        assert Shop.valid_domain?(domain), "expected #{inspect(domain)} to be valid"
      end
    end

    test "rejects hosts that only contain or end with .myshopify.com" do
      for domain <- [
            "acme.myshopify.com.evil.example",
            "evil.example#.myshopify.com",
            "evil.example/.myshopify.com",
            "evil.example?.myshopify.com",
            "user@acme.myshopify.com",
            "acme.myshopify.com\n",
            "-acme.myshopify.com",
            ".myshopify.com"
          ] do
        refute Shop.valid_domain?(domain), "expected #{inspect(domain)} to be invalid"
      end
    end

    test "rejects non-binaries" do
      for domain <- [nil, %{shopify_domain: "acme.myshopify.com"}] do
        refute Shop.valid_domain?(domain), "expected #{inspect(domain)} to be invalid"
      end
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
