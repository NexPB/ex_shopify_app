defmodule ExShopifyApp.AccessToken.CallerTransactionTest do
  @moduledoc """
  The property the detached refresh exists for: a caller transaction that rolls back
  after a refresh cannot undo the persisted token.

  Shopify invalidates the previous refresh token the moment it answers, so a token that
  is exchanged and then rolled away is lost for good — the merchant has to reauthorize.
  Running the refresh in the caller's process made that reachable, because Ecto's
  per-process connection turns the refresh transaction into a nested one that never
  commits on its own.

  Deliberately does NOT use `ExShopifyApp.RepoCase`: under the sandbox's manual and
  shared modes every process ends up on a single connection — shared mode funnels them
  there outright, and in manual mode the `$callers` entry `Task` sets propagates the
  owner's connection to spawned tasks — so the refresh would still nest and this property
  would be untestable. This case puts the sandbox in `:auto` mode instead, where each
  process checks out its own connection and nothing is wrapped in a sandbox transaction.

  Auto-mode connections commit for real, so the test cleans up its row. `async: false`:
  the sandbox mode is repo-global and the test commits to a shared table.
  """
  use ExUnit.Case, async: false

  import Mox
  import ExUnit.CaptureLog, only: [with_log: 1]
  import ExShopifyApp.Factory, only: [build: 2, token_response: 0]
  import ExShopifyApp.HTTPMockHelpers, only: [expect_http_json: 2]

  alias Ecto.Adapters.SQL.Sandbox
  alias ExShopifyApp.AccessToken.Token
  alias ExShopifyApp.{TestRepo, TestStore}

  @domain "callertxn.myshopify.com"

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    Sandbox.mode(TestRepo, :auto)
    on_exit(fn -> Sandbox.mode(TestRepo, :manual) end)

    delete_row()
    TestRepo.insert!(build(:expired_token, shopify_domain: @domain))
    on_exit(&delete_row/0)
    :ok
  end

  test "a caller transaction rolling back cannot undo the refreshed token" do
    expect_http_json(token_response(), times: 1, status: 200)

    {result, log} =
      with_log(fn ->
        TestRepo.transaction(fn ->
          assert {:ok, %Token{refresh_generation: 1, refresh_token: "shprt_new"}} =
                   TestStore.refresh_token(%{shopify_domain: @domain})

          TestRepo.rollback(:caller_aborted)
        end)
      end)

    assert {:error, :caller_aborted} = result
    assert log =~ "inside a caller transaction"
    assert log =~ @domain

    assert {:ok, %Token{refresh_generation: 1, refresh_token: "shprt_new"}} =
             TestStore.fetch_token(@domain)
  end

  test "a caller transaction rolling back cannot undo a migrated token" do
    delete_row()
    TestRepo.insert!(build(:lifetime_token, shopify_domain: @domain))
    expect_http_json(token_response(), times: 1, status: 200)

    {result, log} =
      with_log(fn ->
        TestRepo.transaction(fn ->
          assert {:ok, %Token{refresh_generation: 1}} =
                   TestStore.migrate_token(%{shopify_domain: @domain})

          TestRepo.rollback(:caller_aborted)
        end)
      end)

    assert {:error, :caller_aborted} = result
    assert log =~ "inside a caller transaction"

    assert {:ok, %Token{refresh_generation: 1, refresh_token: "shprt_new"} = token} =
             TestStore.fetch_token(@domain)

    assert not is_nil(token.expires_at)
  end

  defp delete_row do
    TestRepo.query!("DELETE FROM shopify_access_tokens WHERE shopify_domain = $1", [@domain])
  end
end
