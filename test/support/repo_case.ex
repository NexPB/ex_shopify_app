defmodule ExShopifyApp.RepoCase do
  @moduledoc """
  Case template for tests that exercise the real Postgres-backed locked-refresh path of
  `ExShopifyApp.AccessToken.Repo`.

  Each test checks out a connection from the SQL sandbox in shared mode and runs inside a
  transaction that is rolled back on completion, so no explicit table cleanup is needed.
  Shared mode lets the spawned refresh processes (`Task.async_stream`, a `Heartbeat`
  GenServer tick) run on the test's sandbox connection.

  Used with `async: false`, since shared mode and Mox global mode are process-global.
  """

  use ExUnit.CaseTemplate

  import Mox

  using do
    quote do
      import Mox
      import ExShopifyApp.Factory
      import ExShopifyApp.TestHelpers, only: [json_response: 2, stored: 1]

      alias ExShopifyApp.AccessToken.Token
      alias ExShopifyApp.MockTeslaAdapter
      alias ExShopifyApp.{TestRepo, TestStore}
    end
  end

  # Global mode: refresh work runs in spawned processes, so expectations/stubs set in a
  # test must be visible to them.
  setup :set_mox_global

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(ExShopifyApp.TestRepo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(ExShopifyApp.TestRepo, {:shared, self()})
    end

    :ok
  end
end
