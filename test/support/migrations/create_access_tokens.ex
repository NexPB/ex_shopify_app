defmodule ExShopifyApp.TestRepo.Migrations.CreateShopifyAccessTokens do
  @moduledoc """
  The migration contract host apps must run to use `ExShopifyApp.AccessToken.Repo`.

  Kept here (rather than in `priv/repo/migrations`) so the test suite can run it
  against the test repo, while also serving as the documented, copy-pasteable shape
  of the table.
  """

  use Ecto.Migration

  def change do
    create table(:shopify_access_tokens, primary_key: false) do
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

    create(index(:shopify_access_tokens, [:expires_at]))
    create(index(:shopify_access_tokens, [:refresh_token_expires_at]))
  end
end
