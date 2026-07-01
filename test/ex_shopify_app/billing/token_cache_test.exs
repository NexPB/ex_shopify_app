defmodule ExShopifyApp.Billing.TokenCacheTest do
  # async: false — mutates the global :app_events application env and uses the
  # global Tesla mock, so it must not run concurrently with anything else.
  use ExUnit.Case, async: false

  import Tesla.Mock, only: [mock_global: 1]
  import ExShopifyApp.TestHelpers, only: [json_response: 2]

  alias ExShopifyApp.Billing.AppEvents

  @token_url "https://api.shopify.com/auth/access_token"
  @events_url "https://api.shopify.com/app/unstable/events"
  @shop_gid "gid://shopify/Shop/123"

  defmodule StubCache do
    @behaviour ExShopifyApp.Billing.TokenCache

    @impl true
    def fetch, do: {:ok, "stub-token"}
  end

  describe "configured :token_cache" do
    setup do
      previous = Application.get_env(:ex_shopify_app, :app_events)
      Application.put_env(:ex_shopify_app, :app_events, token_cache: StubCache)

      on_exit(fn ->
        if previous do
          Application.put_env(:ex_shopify_app, :app_events, previous)
        else
          Application.delete_env(:ex_shopify_app, :app_events)
        end
      end)
    end

    test "AppEvents.report/5 routes through the configured cache, never hitting the token endpoint" do
      mock_global(fn
        %{method: :post, url: @token_url} ->
          flunk("token endpoint should not be called when a custom cache is configured")

        %{method: :post, url: @events_url, headers: headers} ->
          assert {"authorization", "Bearer stub-token"} in headers
          json_response(%{"accepted" => true}, status: 202)
      end)

      assert {:ok, :accepted} = AppEvents.report("m", @shop_gid, 1, "k")
    end
  end

  describe "app_events_config/0" do
    test "defaults to the supervised TokenServer" do
      Application.delete_env(:ex_shopify_app, :app_events)
      on_exit(fn -> Application.delete_env(:ex_shopify_app, :app_events) end)

      config = ExShopifyApp.app_events_config()
      assert config[:token_cache] == ExShopifyApp.Billing.TokenServer
      assert config[:start_token_cache] == true
    end

    test "start_token_cache: false opts out of auto-supervision" do
      previous = Application.get_env(:ex_shopify_app, :app_events)
      Application.put_env(:ex_shopify_app, :app_events, start_token_cache: false)

      on_exit(fn ->
        if previous do
          Application.put_env(:ex_shopify_app, :app_events, previous)
        else
          Application.delete_env(:ex_shopify_app, :app_events)
        end
      end)

      refute ExShopifyApp.app_events_config()[:start_token_cache]
    end
  end
end
