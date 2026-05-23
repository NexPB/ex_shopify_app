defmodule ExShopifyApp.TestRepo do
  @moduledoc """
  A Postgres-backed `Ecto.Repo` used only by the test suite to exercise the
  database-backed locked refresh path of `ExShopifyApp.AccessToken.Repo`.

  Connection settings are configured at runtime in `test/test_helper.exs`.
  """

  use Ecto.Repo,
    otp_app: :ex_shopify_app,
    adapter: Ecto.Adapters.Postgres
end
