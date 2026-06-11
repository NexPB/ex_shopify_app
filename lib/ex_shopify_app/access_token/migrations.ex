defmodule ExShopifyApp.AccessToken.Migrations do
  @moduledoc """
  Migration helper for the canonical `shopify_access_tokens` table.

  Instead of copying the table definition into your application, write a
  one-line migration that delegates here — the schema can then never drift from
  the `ExShopifyApp.AccessToken.Token` contract the library is compiled against:

      defmodule MyApp.Repo.Migrations.CreateShopifyAccessTokens do
        use Ecto.Migration

        def up, do: ExShopifyApp.AccessToken.Migrations.up()
        def down, do: ExShopifyApp.AccessToken.Migrations.down()
      end

  Both functions are idempotent (`create_if_not_exists` / `drop_if_exists`).
  """

  use Ecto.Migration

  @doc """
  Creates the `shopify_access_tokens` table and its indexes.

  `shopify_domain` is the primary key, so there is exactly one canonical token
  chain per shop/installation.
  """
  @spec up() :: :ok
  def up do
    create_if_not_exists table(:shopify_access_tokens, primary_key: false) do
      add(:shopify_domain, :string, primary_key: true)
      add(:access_token, :text, null: false)
      add(:refresh_token, :text)
      add(:scope, :text)

      add(:expires_in, :integer)
      add(:expires_at, :utc_datetime)
      add(:refresh_token_expires_in, :integer)
      add(:refresh_token_expires_at, :utc_datetime)

      add(:last_refreshed_at, :utc_datetime_usec)
      add(:last_refresh_error, :text)
      add(:refresh_generation, :integer, null: false, default: 0)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(index(:shopify_access_tokens, [:expires_at]))
    create_if_not_exists(index(:shopify_access_tokens, [:refresh_token_expires_at]))

    :ok
  end

  @doc """
  Drops the `shopify_access_tokens` table.
  """
  @spec down() :: :ok
  def down do
    drop_if_exists(table(:shopify_access_tokens))

    :ok
  end
end
