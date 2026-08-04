defmodule ExShopifyApp.AccessToken.HeartbeatTest do
  # async: false — the tick runs in a spawned GenServer, so the Tesla adapter mock is set
  # in Mox global mode and the sandbox in shared mode. RepoCase supplies both, plus the
  # per-test transaction that rolls back the rows a test inserts — batch assertions below
  # rely on seeing only their own rows.
  use ExShopifyApp.RepoCase, async: false

  import ExShopifyApp.HTTPMockHelpers, only: [stub_http_json: 2]

  alias ExShopifyApp.AccessToken.Heartbeat
  alias ExShopifyApp.RecordingStore

  @week 7 * 24 * 60 * 60

  setup do
    # Default: every refresh succeeds, returning a rotated token. Call counts aren't
    # asserted here (tests check resulting token state), so a stub fits; a test can
    # override it with its own stub.
    stub_http_json(
      token_response(%{"access_token" => "shpat_rotated", "refresh_token" => "shprt_rotated"}),
      status: 200
    )

    :ok
  end

  describe "tick event" do
    # A dormant chain is one whose tokens were all issued ~90 days ago: its access token
    # is long hard-expired while its refresh token is only now nearing the cliff. The
    # `:issued` shift derives that state from the factory's default 1h / 90-day lifetimes.
    test "refreshes only chains whose refresh token expires inside the window" do
      insert(:token, shopify_domain: "due.myshopify.com", issued: days_ago(87))
      insert(:token, shopify_domain: "fine.myshopify.com", issued: days_ago(30))
      insert(:lifetime_token, shopify_domain: "lifetime.myshopify.com")

      run_tick()

      assert %Token{refresh_token: "shprt_rotated", refresh_generation: 1} =
               stored("due.myshopify.com")

      assert %Token{refresh_token: "shprt_old", refresh_generation: 0} =
               stored("fine.myshopify.com")

      assert %Token{refresh_token: nil, refresh_generation: 0} =
               stored("lifetime.myshopify.com")
    end

    test "a failing refresh logs and does not crash the process" do
      insert(:token, shopify_domain: "flaky.myshopify.com", issued: days_ago(87))

      stub_http_json(%{"error" => "server"}, status: 503)

      run_tick()

      assert %Token{refresh_token: "shprt_old", refresh_generation: 0} =
               stored("flaky.myshopify.com")
    end

    test "drains the backlog across follow-up ticks when :batch_limit is hit" do
      insert(:token, shopify_domain: "soonest.myshopify.com", issued: days_ago(89))
      insert(:token, shopify_domain: "later.myshopify.com", issued: days_ago(85))

      # batch_limit: 1 caps each batch, so a full first batch re-arms an immediate
      # follow-up tick until the whole backlog is rotated.
      run_tick(batch_limit: 1)

      assert %Token{refresh_generation: 1} = stored("soonest.myshopify.com")
      assert %Token{refresh_generation: 1} = stored("later.myshopify.com")
    end

    test "pages through the backlog :batch_limit at a time, closest expiry first" do
      insert(:token, shopify_domain: "in-1-day.myshopify.com", issued: days_ago(89))
      insert(:token, shopify_domain: "in-3-days.myshopify.com", issued: days_ago(87))
      insert(:token, shopify_domain: "in-5-days.myshopify.com", issued: days_ago(85))

      run_recorded_tick(batch_limit: 2)

      assert_received {:batch, [limit: 2], ["in-1-day.myshopify.com", "in-3-days.myshopify.com"]}
      assert_received {:batch, [limit: 2], ["in-5-days.myshopify.com"]}

      # The second batch came up short, so the drain stops there rather than scanning
      # again — and each rotation extends its chain past the window, so no chain is
      # picked up twice.
      refute_received {:batch, _opts, _domains}
    end

    test "does not scan again when the first batch comes up short of :batch_limit" do
      insert(:token, shopify_domain: "in-3-days.myshopify.com", issued: days_ago(87))
      insert(:token, shopify_domain: "in-4-days.myshopify.com", issued: days_ago(86))

      run_recorded_tick(batch_limit: 5)

      assert_received {:batch, [limit: 5], ["in-3-days.myshopify.com", "in-4-days.myshopify.com"]}

      refute_received {:batch, _opts, _domains}
    end
  end

  defp run_tick(opts \\ []) do
    {:ok, pid} =
      Heartbeat.start_link(
        Keyword.merge(
          [
            store: TestStore,
            window: @week,
            # Long enough that the scheduled tick never fires during the test.
            interval: :timer.hours(6),
            name: nil
          ],
          opts
        )
      )

    send(pid, :tick)
    await_idle(pid)
    GenServer.stop(pid)
  end

  # Same tick, but served by the store shim that reports each scan it answers. The
  # heartbeat is stopped before this returns, so every batch it scanned is already in the
  # test's mailbox — hence `assert_received`, not `assert_receive`.
  defp run_recorded_tick(opts) do
    RecordingStore.record_batches()
    run_tick(Keyword.put(opts, :store, RecordingStore))
  end

  # A full batch re-arms an immediate follow-up `:tick`, so wait until the mailbox is
  # empty (no tick in flight or queued), not just until the first tick is processed.
  defp await_idle(pid) do
    :sys.get_state(pid)

    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, 0} -> :ok
      _ -> await_idle(pid)
    end
  end

  defp days_ago(d), do: DateTime.add(DateTime.utc_now(), -d, :day)
end
