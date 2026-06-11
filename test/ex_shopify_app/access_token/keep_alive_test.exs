defmodule ExShopifyApp.AccessToken.KeepAliveTest do
  # async: false — uses the global Tesla mock and the shared, non-sandboxed Postgres.
  use ExUnit.Case, async: false

  import ExShopifyApp.TestHelpers, only: [json_response: 2]

  alias ExShopifyApp.AccessToken.{KeepAlive, Token}
  alias ExShopifyApp.{TestRepo, TestStore}

  @week 7 * 24 * 60 * 60

  setup do
    TestRepo.delete_all(Token)

    Tesla.Mock.mock_global(fn %{method: :post} ->
      json_response(
        %{
          "access_token" => "shpat_rotated",
          "scope" => "read_orders",
          "expires_in" => 3600,
          "refresh_token" => "shprt_rotated",
          "refresh_token_expires_in" => 7_776_000
        },
        status: 200
      )
    end)

    :ok
  end

  defp store(domain, rt_expires_in) do
    token =
      Token.from_response(
        %{
          "access_token" => "shpat_old",
          "scope" => "read_orders",
          "expires_in" => 3600,
          "refresh_token" => "shprt_old",
          "refresh_token_expires_in" => rt_expires_in
        },
        domain
      )

    :ok = TestStore.put_token(domain, token)
  end

  defp store_lifetime(domain) do
    token = Token.from_response(%{"access_token" => "shpat_lifetime"}, domain)
    :ok = TestStore.put_token(domain, token)
  end

  defp stored(domain) do
    {:ok, token} = TestStore.fetch_token(domain)
    token
  end

  defp run_tick(opts) do
    {:ok, pid} =
      KeepAlive.start_link(
        Keyword.merge(
          [
            store: TestStore,
            repo: TestRepo,
            window: @week,
            # Long enough that the scheduled tick never fires during the test.
            interval: :timer.hours(6),
            name: nil
          ],
          opts
        )
      )

    send(pid, :tick)
    # get_state only returns once the :tick message has been processed.
    :sys.get_state(pid)
    GenServer.stop(pid)
  end

  describe "tick" do
    test "refreshes only chains whose refresh token expires inside the window" do
      store("due.myshopify.com", 3 * 24 * 60 * 60)
      store("fine.myshopify.com", 60 * 24 * 60 * 60)
      store_lifetime("lifetime.myshopify.com")

      run_tick([])

      assert %Token{refresh_token: "shprt_rotated", refresh_generation: 1} =
               stored("due.myshopify.com")

      assert %Token{refresh_token: "shprt_old", refresh_generation: 0} =
               stored("fine.myshopify.com")

      assert %Token{refresh_token: nil, refresh_generation: 0} =
               stored("lifetime.myshopify.com")
    end

    test "a failing refresh logs and does not crash the process" do
      store("flaky.myshopify.com", 3 * 24 * 60 * 60)

      Tesla.Mock.mock_global(fn _ -> json_response(%{"error" => "server"}, status: 503) end)

      run_tick([])

      assert %Token{refresh_token: "shprt_old", refresh_generation: 0} =
               stored("flaky.myshopify.com")
    end

    test "respects :batch_limit, taking the chains closest to expiry first" do
      store("soonest.myshopify.com", 1 * 24 * 60 * 60)
      store("later.myshopify.com", 5 * 24 * 60 * 60)

      run_tick(batch_limit: 1)

      assert %Token{refresh_generation: 1} = stored("soonest.myshopify.com")
      assert %Token{refresh_generation: 0} = stored("later.myshopify.com")
    end
  end
end
