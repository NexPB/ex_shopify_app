defmodule ExShopifyApp.TestRepo do
  @moduledoc """
  A Postgres-backed `Ecto.Repo` used only by the test suite to exercise the
  database-backed locked refresh path of `ExShopifyApp.AccessToken.Repo`.

  Connection settings are configured in `config/test.exs`.
  """

  use Ecto.Repo,
    otp_app: :ex_shopify_app,
    adapter: Ecto.Adapters.Postgres
end
