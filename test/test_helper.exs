ExUnit.start(capture_log: true)

# Tesla HTTP calls are routed through this Mox-backed adapter in the test env (see
# config/test.exs). The adapter implements the `Tesla.Adapter` behaviour, so tests set
# expectations on its `call/2` callback both to stub responses and to assert call counts.
Mox.defmock(ExShopifyApp.MockTeslaAdapter, for: Tesla.Adapter)

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

# Sandbox in manual mode: each case template (see ExShopifyApp.RepoCase) checks out its
# own connection. Test helpers (json_response/2, stored/1) live in
# ExShopifyApp.TestHelpers (test/support/test_helpers.ex).
Ecto.Adapters.SQL.Sandbox.mode(ExShopifyApp.TestRepo, :manual)
