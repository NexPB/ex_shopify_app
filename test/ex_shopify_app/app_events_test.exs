defmodule ExShopifyApp.AppEventsTest do
  # async: false — the client_credentials JWT lives in the singleton TokenServer
  # process, and the token fetch runs in that process, so we use a global Mox stub
  # (via `set_mox_from_context`, which enables global mode for non-async tests) and
  # must not run concurrently with anything else touching it.
  use ExUnit.Case, async: false

  import Mox
  import ExShopifyApp.TestHelpers, only: [json_response: 2]
  import ExShopifyApp.HTTPMockHelpers, only: [stub_http: 1]

  alias ExShopifyApp.AppEvents
  alias ExShopifyApp.AppEvents.Event
  alias ExShopifyApp.AppEvents.TokenServer

  @token_url "https://api.shopify.com/auth/access_token"
  @events_url "https://api.shopify.com/app/unstable/events"
  @shop_gid "gid://shopify/Shop/123"

  # The App Events token endpoint returns only a JWT; the lifetime lives in its `exp`
  # claim. Build a well-formed one that expires far in the future so it stays cached.
  @access_token "header." <>
                  Base.url_encode64(JSON.encode!(%{"exp" => 32_503_680_000}), padding: false) <>
                  ".sig"

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    TokenServer.reset()
    :ok
  end

  describe "report/2" do
    test "fetches a token then posts the usage event, returning {:ok, body} on 202" do
      stub_http(fn
        %{method: :post, url: @token_url, body: body} ->
          params = JSON.decode!(body)
          assert params["client_id"] == "test-api-key"
          assert params["client_secret"] == "test-api-secret"
          assert params["grant_type"] == "client_credentials"
          {:ok, json_response(%{"access_token" => @access_token}, status: 200)}

        %{method: :post, url: @events_url, headers: headers, body: body} ->
          assert {"authorization", "Bearer #{@access_token}"} in headers
          params = JSON.decode!(body)
          assert params["shop_id"] == @shop_gid
          assert params["event_handle"] == "passes_active"
          assert params["idempotency_key"] == "passes_active:1:2026-06"
          assert params["attributes"] == %{"value" => 7}
          assert params["timestamp"] == "2026-06-28T00:00:00Z"
          {:ok, json_response(%{"accepted" => true}, status: 202)}
      end)

      assert {:ok, :accepted} =
               %Event{
                 event_handle: "passes_active",
                 value: 7,
                 idempotency_key: "passes_active:1:2026-06",
                 timestamp: ~U[2026-06-28 00:00:00Z]
               }
               |> AppEvents.report(%{shop_gid: @shop_gid})
    end

    test "returns {:error, _} on a non-202 event response" do
      stub_http(fn
        %{url: @token_url} ->
          {:ok, json_response(%{"access_token" => @access_token}, status: 200)}

        %{url: @events_url} ->
          {:ok, json_response(%{"error" => "bad"}, status: 422)}
      end)

      assert {:error, %Tesla.Env{status: 422}} = report_event(1, "k")
    end

    test "caches the token across reports, fetching it only once" do
      counter = :counters.new(1, [])

      stub_http(fn
        %{url: @token_url} ->
          :counters.add(counter, 1, 1)
          {:ok, json_response(%{"access_token" => @access_token}, status: 200)}

        %{url: @events_url} ->
          {:ok, json_response(%{"accepted" => true}, status: 202)}
      end)

      assert {:ok, _} = report_event(1, "k1")
      assert {:ok, _} = report_event(2, "k2")

      assert :counters.get(counter, 1) == 1
    end

    test "surfaces a token-endpoint failure without calling the events endpoint" do
      stub_http(fn %{url: @token_url} ->
        {:ok, json_response(%{"error" => "invalid_client"}, status: 401)}
      end)

      assert {:error, %Tesla.Env{status: 401}} = report_event(1, "k")
    end

    test "treats a 200 with an undecodable token as an error, without calling events" do
      stub_http(fn
        %{url: @token_url} ->
          {:ok, json_response(%{"access_token" => "not-a-jwt"}, status: 200)}

        %{url: @events_url} ->
          flunk("events endpoint must not be called when the token can't be decoded")
      end)

      assert {:error, %Tesla.Env{status: 200}} = report_event(1, "k")
    end
  end

  defp report_event(value, idempotency_key) do
    %Event{event_handle: "m", value: value, idempotency_key: idempotency_key}
    |> AppEvents.report(%{shop_gid: @shop_gid})
  end
end
