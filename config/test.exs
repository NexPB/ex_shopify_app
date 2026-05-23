import Config

# Keep test output readable: skip Ecto's per-query debug logging.
config :logger, level: :warning

# Route all Tesla calls through the mock adapter in the test env.
config :tesla, adapter: Tesla.Mock

# --- Ecto test repo --------------------------------------------------------
#
# The Ecto-backed store is exercised against a real Postgres so that
# `SELECT ... FOR UPDATE` row locking actually contends across processes. We do
# not use the SQL sandbox: real cross-connection row locks are the behaviour
# under test, so the tests clean the table explicitly between runs.
config :ex_shopify_app, ExShopifyApp.TestRepo,
  url: "ecto://postgres:postgres@127.0.0.1:5432/ex_shopify_app_test",
  pool_size: 10

# Credentials read by ExShopifyApp.api_key/0 and api_secret/0.
config :ex_shopify_app,
  api_key: "test-api-key",
  api_secret: "test-api-secret"
