defmodule ExShopifyApp.TestStore do
  @moduledoc "An Ecto-backed store wired to `ExShopifyApp.TestRepo` for the test suite."

  use ExShopifyApp.AccessToken.Repo,
    repo: ExShopifyApp.TestRepo
end
