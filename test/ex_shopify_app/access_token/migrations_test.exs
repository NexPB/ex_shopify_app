defmodule ExShopifyApp.AccessToken.MigrationsTest do
  # async: false — runs real migrations against the shared test database. The suite puts
  # the sandbox in :manual mode (see test_helper.exs), but the migrator spawns its own
  # task/connection that can't be served under manual mode. Flip this repo to :auto for the
  # test so DDL runs and commits against normal pooled connections, then restore :manual.
  use ExUnit.Case, async: false

  alias ExShopifyApp.TestRepo

  @version 20_990_101_000_000

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :auto)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual) end)
    :ok
  end

  defmodule HostMigration do
    @moduledoc "The one-liner migration shape host applications are told to write."

    use Ecto.Migration

    def up, do: ExShopifyApp.AccessToken.Migrations.up()
    def down, do: ExShopifyApp.AccessToken.Migrations.down()
  end

  defp table_oid do
    TestRepo.query!("SELECT to_regclass('shopify_access_tokens')").rows |> hd() |> hd()
  end

  # The version is recorded in the table comment; nil once the table is dropped.
  defp migrated_version do
    TestRepo.query!(
      "SELECT pg_catalog.obj_description(to_regclass('shopify_access_tokens'), 'pg_class')"
    ).rows
    |> hd()
    |> hd()
  end

  test "up/0 and down/0 create and drop the shopify_access_tokens table" do
    # The table already exists from test_helper's initial migration; up/0 must be
    # idempotent against it and the recorded version is the current version.
    refute is_nil(table_oid())
    assert migrated_version() == "1"

    # Already on the latest version: re-running up/0 is a no-op.
    Ecto.Migrator.up(TestRepo, @version, HostMigration)
    refute is_nil(table_oid())
    assert migrated_version() == "1"

    Ecto.Migrator.down(TestRepo, @version, HostMigration)
    assert is_nil(table_oid())
    # The version comment goes away with the table.
    assert is_nil(migrated_version())

    # Restore the schema for the rest of the suite (shared database).
    Ecto.Migrator.up(TestRepo, @version, HostMigration)
    refute is_nil(table_oid())
    assert migrated_version() == "1"

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
