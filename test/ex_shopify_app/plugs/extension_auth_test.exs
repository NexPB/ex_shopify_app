defmodule ExShopifyApp.Plugs.ExtensionAuthTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias ExShopifyApp.Plugs.ExtensionAuth
  alias Plug.Conn

  # The claims of a checkout or customer account UI extension session token.
  defp claims(overrides \\ %{}) do
    now = System.system_time(:second)

    Map.merge(
      %{
        "dest" => "shop.myshopify.com",
        "aud" => ExShopifyApp.api_key(),
        "exp" => now + 300,
        "nbf" => now - 5,
        "iat" => now - 5,
        "jti" => "6c992878-dbaf-48d1-bb9d-6d9b59814fd1"
      },
      overrides
    )
  end

  defp sign(claims) do
    {_, token} =
      ExShopifyApp.api_secret()
      |> JOSE.JWK.from_oct()
      |> JOSE.JWT.sign(%{"alg" => "HS256"}, claims)
      |> JOSE.JWS.compact()

    token
  end

  defp run(claims, scheme \\ "Bearer") do
    :post
    |> conn("/extension")
    |> Conn.put_req_header("authorization", scheme <> " " <> sign(claims))
    |> ExtensionAuth.call(ExtensionAuth.init([]))
  end

  test "authenticates an extension session token" do
    conn = run(claims())

    refute conn.halted
    assert ExShopifyApp.Token.Plug.current_resource(conn) == "shop.myshopify.com"
  end

  test "rejects a token for another app" do
    assert run(claims(%{"aud" => "other-api-key"})).status == 401
  end

  test "rejects a token without dest, exp or nbf" do
    for claim <- ["dest", "exp", "nbf"] do
      assert run(Map.delete(claims(), claim)).status == 401
    end
  end

  test "reads the bearer scheme in any case" do
    refute run(claims(), "bearer").halted
  end

  test "rejects another scheme, or a scheme followed by a colon" do
    assert run(claims(), "Basic").status == 401
    assert run(claims(), "Bearer:").status == 401
  end

  test "rejects a repeated authorization header" do
    header = "Bearer " <> sign(claims())
    conn = conn(:post, "/extension")

    conn = %{conn | req_headers: [{"authorization", header}, {"authorization", header}]}

    assert ExtensionAuth.call(conn, ExtensionAuth.init([])).status == 401
  end

  test "rejects a request without a token" do
    conn = :post |> conn("/extension") |> ExtensionAuth.call(ExtensionAuth.init([]))

    assert conn.halted
    assert conn.status == 401
  end
end
