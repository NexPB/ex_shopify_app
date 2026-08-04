ExUnit.start(capture_log: true)

# The Tesla adapter Mox mock (ExShopifyApp.HTTPMock) is defined in test/support/mocks.ex
# and wired in as the Tesla adapter in config/test.exs. Tests drive it through the
# ExShopifyApp.HTTPMockHelpers wrappers (stub_http_json/expect_http_json/expect_http_call).

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
