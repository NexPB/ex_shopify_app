ExUnit.start()

{:ok, _} = ExShopifyApp.TestRepo.start_link()

# Recreate the schema from scratch on every run so the table always matches the
# documented migration contract, regardless of prior state.
Ecto.Adapters.SQL.query!(
  ExShopifyApp.TestRepo,
  "DROP TABLE IF EXISTS shopify_access_tokens, schema_migrations CASCADE"
)

Ecto.Migrator.run(
  ExShopifyApp.TestRepo,
  [{0, ExShopifyApp.TestRepo.Migrations.CreateShopifyAccessTokens}],
  :up,
  all: true
)
