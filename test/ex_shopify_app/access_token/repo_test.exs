defmodule ExShopifyApp.AccessToken.RepoTest do
  # async: false — refreshes use the global Tesla mock (concurrent refreshes run in
  # spawned processes) and a shared, non-sandboxed Postgres so FOR UPDATE row locks
  # actually contend across connections.
  use ExUnit.Case, async: false

  import ExShopifyApp.TestHelpers, only: [json_response: 2]

  alias ExShopifyApp.AccessToken.Token
  alias ExShopifyApp.{TestRepo, TestStore}

  setup do
    TestRepo.delete_all(Token)
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    %{counter: counter}
  end

  # --- helpers ---------------------------------------------------------------

  defp token(domain, opts) do
    issued = Keyword.get(opts, :issued)
    expires_in = Keyword.get(opts, :expires_in, 3600)
    rt_expires_in = Keyword.get(opts, :rt_expires_in, 7_776_000)

    token =
      Token.from_response(
        %{
          "access_token" => Keyword.get(opts, :access_token, "shpat_old"),
          "scope" => "read_orders",
          "expires_in" => expires_in,
          "refresh_token" => Keyword.get(opts, :refresh_token, "shprt_old"),
          "refresh_token_expires_in" => rt_expires_in
        },
        domain
      )

    if is_struct(issued, DateTime) do
      %{
        token
        | expires_at: DateTime.add(issued, expires_in),
          refresh_token_expires_at: DateTime.add(issued, rt_expires_in)
      }
    else
      token
    end
  end

  defp store(domain, opts), do: :ok = TestStore.put_token(domain, token(domain, opts))

  defp stored(domain) do
    {:ok, token} = TestStore.fetch_token(domain)
    token
  end

  defp calls(counter), do: Agent.get(counter, & &1)

  defp mock_refresh(counter, opts \\ []) do
    delay = Keyword.get(opts, :delay, 0)

    Tesla.Mock.mock_global(fn %{method: :post} ->
      Agent.update(counter, &(&1 + 1))
      if delay > 0, do: Process.sleep(delay)

      json_response(
        %{
          "access_token" => "shpat_new",
          "scope" => "read_orders",
          "expires_in" => 3600,
          "refresh_token" => "shprt_new",
          "refresh_token_expires_in" => 7_776_000
        },
        status: 200
      )
    end)
  end

  defp hours_ago(h), do: DateTime.add(DateTime.utc_now(), -h, :hour)

  # --- put_token / fetch_token ----------------------------------------------

  describe "put_token/2 and fetch_token/1" do
    test "fetch_token returns {:error, :no_token} for a missing row" do
      assert {:error, :no_token} = TestStore.fetch_token("missing.myshopify.com")
    end

    test "put_token upserts by shopify_domain" do
      domain = "shop.myshopify.com"
      store(domain, access_token: "shpat_first")
      store(domain, access_token: "shpat_second")

      assert TestRepo.aggregate(Token, :count) == 1
      assert %Token{access_token: "shpat_second"} = stored(domain)
    end

    test "put_token normalizes a https:// prefixed domain" do
      :ok =
        TestStore.put_token("https://shop.myshopify.com", token("https://shop.myshopify.com", []))

      assert {:ok, %Token{shopify_domain: "shop.myshopify.com"}} =
               TestStore.fetch_token("shop.myshopify.com")
    end
  end

  # --- valid_token ------------------------------------------------------------

  describe "valid_token/2" do
    test "no stored token returns {:error, :no_token}" do
      assert {:error, :no_token} = TestStore.valid_token(%{shopify_domain: "nope.myshopify.com"})
    end

    test "a fresh token is returned without an HTTP call", %{counter: counter} do
      mock_refresh(counter)
      domain = "fresh.myshopify.com"
      store(domain, access_token: "shpat_fresh")

      assert {:ok, %Token{access_token: "shpat_fresh", refresh_generation: 0}} =
               TestStore.valid_token(%{shopify_domain: domain})

      assert calls(counter) == 0
    end

    test "a hard-expired token refreshes and persists before returning", %{counter: counter} do
      mock_refresh(counter)
      domain = "expired.myshopify.com"
      store(domain, issued: hours_ago(2))

      assert {:ok,
              %Token{access_token: "shpat_new", refresh_token: "shprt_new", refresh_generation: 1}} =
               TestStore.valid_token(%{shopify_domain: domain})

      assert calls(counter) == 1
      # Persisted before returning.
      assert %Token{refresh_token: "shprt_new", refresh_generation: 1} = stored(domain)
    end

    test "a stale token refreshes synchronously and persists by default", %{counter: counter} do
      mock_refresh(counter)
      domain = "stale.myshopify.com"
      # 3300s into a 3600s lifetime: inside the soft window, not yet hard-expired.
      store(domain, issued: DateTime.add(DateTime.utc_now(), -3300, :second))

      assert {:ok, %Token{access_token: "shpat_new"}} =
               TestStore.valid_token(%{shopify_domain: domain}, soft_window: [jitter: 0])

      assert calls(counter) == 1
      assert %Token{refresh_token: "shprt_new"} = stored(domain)
    end

    test "an expired refresh token returns :reauthorization_required without an HTTP call", %{
      counter: counter
    } do
      mock_refresh(counter)
      domain = "dead.myshopify.com"
      store(domain, issued: hours_ago(3000), rt_expires_in: 7_776_000)

      assert {:error, :reauthorization_required} =
               TestStore.valid_token(%{shopify_domain: domain})

      assert calls(counter) == 0
    end
  end

  # --- refresh_token: Shopify error handling ---------------------------------

  describe "refresh_token/2 Shopify errors" do
    test "invalid_grant maps to :reauthorization_required and leaves the token unchanged" do
      domain = "ig.myshopify.com"
      store(domain, issued: hours_ago(2))

      Tesla.Mock.mock_global(fn _ ->
        json_response(%{"error" => "invalid_grant"}, status: 400)
      end)

      assert {:error, :reauthorization_required} =
               TestStore.refresh_token(%{shopify_domain: domain})

      assert %Token{refresh_token: "shprt_old", refresh_generation: 0} = stored(domain)
    end

    test "a 5xx maps to {:refresh_failed, _}, leaves the token, and records last_refresh_error" do
      domain = "boom.myshopify.com"
      store(domain, issued: hours_ago(2))
      Tesla.Mock.mock_global(fn _ -> json_response(%{"error" => "server"}, status: 503) end)

      assert {:error, {:refresh_failed, %Tesla.Env{status: 503}}} =
               TestStore.refresh_token(%{shopify_domain: domain})

      token = stored(domain)
      assert token.refresh_token == "shprt_old"
      assert token.refresh_generation == 0
      assert token.last_refresh_error =~ "refresh_failed:http_503"
    end

    test "stale_while_error returns the still-valid token when a refresh fails" do
      domain = "swr.myshopify.com"
      store(domain, issued: DateTime.add(DateTime.utc_now(), -3300, :second))
      Tesla.Mock.mock_global(fn _ -> json_response(%{"error" => "server"}, status: 503) end)

      assert {:ok, %Token{access_token: "shpat_old"}} =
               TestStore.valid_token(%{shopify_domain: domain},
                 soft_window: [jitter: 0],
                 stale_while_error: true
               )
    end
  end

  # --- concurrency ------------------------------------------------------------

  describe "concurrent refreshes" do
    test "for one shop produce exactly one Shopify call and one generation bump", %{
      counter: counter
    } do
      domain = "concurrent.myshopify.com"
      store(domain, issued: hours_ago(2))
      mock_refresh(counter, delay: 30)

      results =
        1..10
        |> Task.async_stream(fn _ -> TestStore.refresh_token(%{shopify_domain: domain}) end,
          max_concurrency: 10,
          timeout: 10_000
        )
        |> Enum.map(fn {:ok, res} -> res end)

      assert Enum.all?(results, &match?({:ok, %Token{refresh_token: "shprt_new"}}, &1))
      assert calls(counter) == 1
      assert %Token{refresh_generation: 1} = stored(domain)
    end

    test "for different shops proceed independently", %{counter: counter} do
      store("a.myshopify.com", issued: hours_ago(2))
      store("b.myshopify.com", issued: hours_ago(2))
      mock_refresh(counter, delay: 10)

      t1 = Task.async(fn -> TestStore.refresh_token(%{shopify_domain: "a.myshopify.com"}) end)
      t2 = Task.async(fn -> TestStore.refresh_token(%{shopify_domain: "b.myshopify.com"}) end)

      assert {:ok, %Token{}} = Task.await(t1)
      assert {:ok, %Token{}} = Task.await(t2)
      assert calls(counter) == 2
    end
  end

  # --- persistence failure after a successful refresh ------------------------

  test "persistence failure after Shopify success is critical and emits telemetry", %{
    counter: counter
  } do
    domain = "persistfail.myshopify.com"
    store(domain, issued: hours_ago(2))
    mock_refresh(counter)

    handler = "persist-failed-#{System.unique_integer([:positive])}"
    test_pid = self()

    :telemetry.attach(
      handler,
      [:ex_shopify_app, :access_token, :refresh, :persistence_failed],
      fn event, measurements, meta, _ ->
        send(test_pid, {:telemetry, event, measurements, meta})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert {:error, {:token_persistence_failed_after_refresh, :persist_boom}} =
             ExShopifyApp.FailingStore.refresh_token(%{shopify_domain: domain})

    # Shopify was called, but the row is untouched (rolled back).
    assert calls(counter) == 1
    assert %Token{refresh_token: "shprt_old", refresh_generation: 0} = stored(domain)

    assert_receive {:telemetry, [:ex_shopify_app, :access_token, :refresh, :persistence_failed],
                    _m, %{shopify_domain: ^domain}}
  end

  # --- lock timeout -----------------------------------------------------------

  test "a held row lock surfaces {:error, {:lock_timeout, _}}" do
    domain = "locked.myshopify.com"
    store(domain, issued: hours_ago(2))

    parent = self()

    holder =
      spawn(fn ->
        TestRepo.transaction(fn ->
          TestRepo.query!(
            "SELECT shopify_domain FROM shopify_access_tokens WHERE shopify_domain = $1 FOR UPDATE",
            [domain]
          )

          send(parent, :locked)

          receive do
            :release -> :ok
          after
            5_000 -> :ok
          end
        end)
      end)

    assert_receive :locked, 2_000

    assert {:error, {:lock_timeout, _reason}} =
             TestStore.refresh_token(%{shopify_domain: domain}, lock_timeout: 100)

    send(holder, :release)
  end
end
