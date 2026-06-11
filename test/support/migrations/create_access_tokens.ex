defmodule ExShopifyApp.TestRepo.Migrations.CreateShopifyAccessTokens do
  @moduledoc """
  The migration contract host apps must run to use `ExShopifyApp.AccessToken.Repo`.

  Delegates to `ExShopifyApp.AccessToken.Migrations` — the same helper host
  applications are told to call — so the schema the suite runs against can never
  drift from the documented contract.
  """

  use Ecto.Migration

  def up, do: ExShopifyApp.AccessToken.Migrations.up()
  def down, do: ExShopifyApp.AccessToken.Migrations.down()
end
