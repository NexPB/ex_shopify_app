defmodule ExShopifyApp.AppEvents.TokenServerTest do
  use ExUnit.Case, async: true

  alias ExShopifyApp.AppEvents.TokenServer

  test "redacts the cached token from the process status" do
    server =
      start_supervised!({TokenServer, name: nil, fetcher: fn -> {:ok, "secret-jwt", 3600} end})

    assert {:ok, "secret-jwt"} = TokenServer.fetch(server)

    status = :sys.get_status(server)
    refute inspect(status) =~ "secret-jwt"
    assert inspect(status) =~ ":redacted"
  end
end
