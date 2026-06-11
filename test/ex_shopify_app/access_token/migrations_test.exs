defmodule ExShopifyApp.AccessToken.MigrationsTest do
  # async: false — migrates the shared, non-sandboxed test database.
  use ExUnit.Case, async: false

  alias ExShopifyApp.TestRepo

  @version 20_990_101_000_000

  defmodule HostMigration do
    @moduledoc "The one-liner migration shape host applications are told to write."

    use Ecto.Migration

    def up, do: ExShopifyApp.AccessToken.Migrations.up()
    def down, do: ExShopifyApp.AccessToken.Migrations.down()
  end

  defp table_oid do
    TestRepo.query!("SELECT to_regclass('shopify_access_tokens')").rows |> hd() |> hd()
  end

  test "up/0 and down/0 create and drop the shopify_access_tokens table" do
    # The table already exists from test_helper's initial migration; up/0 must be
    # idempotent against it.
    refute is_nil(table_oid())

    Ecto.Migrator.up(TestRepo, @version, HostMigration)
    refute is_nil(table_oid())

    Ecto.Migrator.down(TestRepo, @version, HostMigration)
    assert is_nil(table_oid())

    # Restore the schema for the rest of the suite (shared database).
    Ecto.Migrator.up(TestRepo, @version, HostMigration)
    refute is_nil(table_oid())

    columns =
      TestRepo.query!("""
      SELECT column_name, data_type
      FROM information_schema.columns
      WHERE table_name = 'shopify_access_tokens'
      ORDER BY column_name
      """).rows

    assert [
             "access_token",
             "expires_at",
             "expires_in",
             "inserted_at",
             "last_refresh_error",
             "last_refreshed_at",
             "refresh_generation",
             "refresh_token",
             "refresh_token_expires_at",
             "refresh_token_expires_in",
             "scope",
             "shopify_domain",
             "updated_at"
           ] == Enum.map(columns, &hd/1)

    assert {"expires_at", "timestamp without time zone"} in Enum.map(columns, &List.to_tuple/1)
  end
end
