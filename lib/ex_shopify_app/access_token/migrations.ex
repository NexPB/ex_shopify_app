# Ecto.Migration ships with ecto_sql, which is an optional dependency — only
# define the helper when the host application has it.
if Code.ensure_loaded?(Ecto.Migration) do
  defmodule ExShopifyApp.AccessToken.Migrations do
    @moduledoc """
    Versioned migrations for the canonical `shopify_access_tokens` table.

    Instead of copying the table definition into your application, write a
    one-line migration that delegates here — the schema can then never drift from
    the `ExShopifyApp.AccessToken.Token` contract the library is compiled against:

        defmodule MyApp.Repo.Migrations.CreateShopifyAccessTokens do
          use Ecto.Migration

          def up, do: ExShopifyApp.AccessToken.Migrations.up()
          def down, do: ExShopifyApp.AccessToken.Migrations.down()
        end

    This runs every versioned migration up to the latest version.

    ## Upgrading

    As the library evolves, new schema versions are released. The migrated version
    is recorded in the table's comment, so re-running `up/0` is a no-op once you are
    on the latest version. To pin a migration to a specific version — for example
    when a new release adds version 2 — generate a new migration and pass `version`:

        defmodule MyApp.Repo.Migrations.UpgradeShopifyAccessTokensToV2 do
          use Ecto.Migration

          def up, do: ExShopifyApp.AccessToken.Migrations.up(version: 2)
          def down, do: ExShopifyApp.AccessToken.Migrations.down(version: 2)
        end

    Requires `:ecto_sql` (an optional dependency of this library): this module is
    only compiled when `Ecto.Migration` is available.
    """

    use Ecto.Migration

    @initial_version 1
    @current_version 1
    @table "shopify_access_tokens"

    @doc """
    Migrates storage up to the latest version (or to `version` if given).

    Only the versions between the currently migrated version and the target are
    run, so this is safe to re-run and to call on an already up-to-date database.
    """
    @spec up(keyword()) :: :ok
    def up(opts \\ []) when is_list(opts) do
      version = Keyword.get(opts, :version, @current_version)
      initial = migrated_version(opts)

      cond do
        initial == 0 -> change(@initial_version..version, :up)
        initial < version -> change((initial + 1)..version, :up)
        true -> :ok
      end
    end

    @doc """
    Migrates storage down to (and including) `version`, defaulting to the first
    version — i.e. dropping everything.
    """
    @spec down(keyword()) :: :ok
    def down(opts \\ []) when is_list(opts) do
      version = Keyword.get(opts, :version, @initial_version)
      initial = max(migrated_version(opts), @initial_version)

      if initial >= version do
        change(initial..version//-1, :down)
      else
        :ok
      end
    end

    @doc """
    Identifies the last migrated version, or `0` if the table has never been
    migrated. The version is read from the `shopify_access_tokens` table comment.
    """
    @spec migrated_version(keyword()) :: non_neg_integer()
    def migrated_version(_opts \\ []) do
      query = "SELECT pg_catalog.obj_description(to_regclass('#{@table}'), 'pg_class')"

      case repo().query(query, [], log: false) do
        {:ok, %{rows: [[version]]}} when is_binary(version) -> String.to_integer(version)
        _ -> 0
      end
    end

    defp change(range, direction) do
      for index <- range do
        pad = String.pad_leading(to_string(index), 2, "0")

        [__MODULE__, "V#{pad}"]
        |> Module.concat()
        |> apply(direction, [])
      end

      case direction do
        :up -> record_version(Enum.max(range))
        :down -> record_version(Enum.min(range) - 1)
      end
    end

    # Version 0 means the table no longer exists (fully migrated down); nothing to
    # record a comment on.
    defp record_version(0), do: :ok

    defp record_version(version) do
      execute("COMMENT ON TABLE #{@table} IS '#{version}'")
    end
  end
end
