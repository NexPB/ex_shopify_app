defmodule ExShopifyApp.AccessToken.HeartbeatTest do
  # async: false — the tick runs in a spawned GenServer, so the Tesla adapter mock is set
  # in Mox global mode, against the shared, non-sandboxed Postgres. RepoCase supplies the
  # shared imports/aliases, global Mox mode, and the per-test table cleanup.
  use ExShopifyApp.RepoCase, async: false

  alias ExShopifyApp.AccessToken.Heartbeat

  @week 7 * 24 * 60 * 60

  setup do
    # Default: every refresh succeeds, returning a rotated token. Call counts aren't
    # asserted here (tests check resulting token state), so a stub fits; a test can
    # override it with its own stub.
    stub(MockTeslaAdapter, :call, fn %{method: :post}, _opts ->
      {:ok,
       json_response(
         token_response(%{"access_token" => "shpat_rotated", "refresh_token" => "shprt_rotated"}),
         status: 200
       )}
    end)

    :ok
  end

  describe "tick" do
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

      stub(MockTeslaAdapter, :call, fn _env, _opts ->
        {:ok, json_response(%{"error" => "server"}, status: 503)}
      end)

      run_tick()

      assert %Token{refresh_token: "shprt_old", refresh_generation: 0} =
               stored("flaky.myshopify.com")
    end

    test "drains the backlog across follow-up ticks when :batch_limit is hit" do
      insert(:token, shopify_domain: "soonest.myshopify.com", issued: days_ago(89))
      insert(:token, shopify_domain: "later.myshopify.com", issued: days_ago(85))

      # batch_limit: 1 caps each batch, so a full first batch re-arms an immediate
      # follow-up tick until the whole backlog is rotated. (Closest-expiry-first
      # ordering of the batch itself is covered in RepoTest's `expiring_domains/2`.)
      run_tick(batch_limit: 1)

      assert %Token{refresh_generation: 1} = stored("soonest.myshopify.com")
      assert %Token{refresh_generation: 1} = stored("later.myshopify.com")
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
