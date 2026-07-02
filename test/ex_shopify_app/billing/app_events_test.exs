defmodule ExShopifyApp.Billing.AppEventsTest do
  # async: false — the client_credentials JWT lives in the singleton TokenServer
  # process, and the token fetch runs in that process, so we use a global Mox stub
  # (via `set_mox_from_context`, which enables global mode for non-async tests) and
  # must not run concurrently with anything else touching it.
  use ExUnit.Case, async: false

  import Mox
  import ExShopifyApp.TestHelpers, only: [json_response: 2]
  import ExShopifyApp.HTTPMockHelpers, only: [stub_http: 1]

  alias ExShopifyApp.Billing.AppEvents
  alias ExShopifyApp.Billing.TokenServer

  @token_url "https://api.shopify.com/auth/access_token"
  @events_url "https://api.shopify.com/app/unstable/events"
  @shop_gid "gid://shopify/Shop/123"

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    TokenServer.reset()
    :ok
  end

  describe "report/5" do
    test "fetches a token then posts the usage event, returning {:ok, body} on 202" do
      stub_http(fn
        %{method: :post, url: @token_url, body: body} ->
          params = JSON.decode!(body)
          assert params["client_id"] == "test-api-key"
          assert params["client_secret"] == "test-api-secret"
          assert params["grant_type"] == "client_credentials"
          {:ok, json_response(%{"access_token" => "jwt-abc", "expires_in" => 3600}, status: 200)}

        %{method: :post, url: @events_url, headers: headers, body: body} ->
          assert {"authorization", "Bearer jwt-abc"} in headers
          params = JSON.decode!(body)
          assert params["shop_id"] == @shop_gid
          assert params["event_handle"] == "passes_active"
          assert params["idempotency_key"] == "passes_active:1:2026-06"
          assert params["attributes"] == %{"value" => 7}
          assert params["timestamp"] == "2026-06-28T00:00:00Z"
          {:ok, json_response(%{"accepted" => true}, status: 202)}
      end)

      assert {:ok, :accepted} =
               AppEvents.report(
                 "passes_active",
                 @shop_gid,
                 7,
                 "passes_active:1:2026-06",
                 timestamp: ~U[2026-06-28 00:00:00Z]
               )
    end

    test "returns {:error, _} on a non-202 event response" do
      stub_http(fn
        %{url: @token_url} ->
          {:ok, json_response(%{"access_token" => "jwt-abc", "expires_in" => 3600}, status: 200)}

        %{url: @events_url} ->
          {:ok, json_response(%{"error" => "bad"}, status: 422)}
      end)

      assert {:error, %Tesla.Env{status: 422}} = AppEvents.report("m", @shop_gid, 1, "k")
    end

    test "caches the token across reports, fetching it only once" do
      counter = :counters.new(1, [])

      stub_http(fn
        %{url: @token_url} ->
          :counters.add(counter, 1, 1)
          {:ok, json_response(%{"access_token" => "jwt-abc", "expires_in" => 3600}, status: 200)}

        %{url: @events_url} ->
          {:ok, json_response(%{"accepted" => true}, status: 202)}
      end)

      assert {:ok, _} = AppEvents.report("m", @shop_gid, 1, "k1")
      assert {:ok, _} = AppEvents.report("m", @shop_gid, 2, "k2")

      assert :counters.get(counter, 1) == 1
    end

    test "surfaces a token-endpoint failure without calling the events endpoint" do
      stub_http(fn %{url: @token_url} ->
        {:ok, json_response(%{"error" => "invalid_client"}, status: 401)}
      end)

      assert {:error, %Tesla.Env{status: 401}} = AppEvents.report("m", @shop_gid, 1, "k")
    end
  end
end
