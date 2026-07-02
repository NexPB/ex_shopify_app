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

defmodule ExShopifyApp.TestHelpers do
  @moduledoc """
  Test helpers. We avoid Tesla's own JSON response helpers (`Tesla.Mock.json/2` and
  `Tesla.Test.json/2`) because they require Jason, which the library intentionally
  does not depend on; instead we build responses with the built-in `JSON` engine the
  client itself uses.
  """

  @doc """
  Build a `Tesla.Env` JSON response for use as a Mox stub/`expect_tesla_call` return.

  Returns a bare `%Tesla.Env{}`. `Tesla.Test.expect_tesla_call(returns: ...)` accepts
  it directly; inside a raw `Mox.stub` callback wrap it as `{:ok, json_response(...)}`
  to satisfy the `Tesla.Adapter.call/2` contract.
  """
  def json_response(body, opts \\ []) do
    %Tesla.Env{
      status: Keyword.get(opts, :status, 200),
      body: JSON.encode!(body),
      headers: [{"content-type", "application/json"}]
    }
  end
end
