defmodule ExShopifyApp.TokenTest do
  use ExUnit.Case, async: true

  alias ExShopifyApp.Token

  defp claims(overrides \\ %{}) do
    now = System.system_time(:second)

    Map.merge(
      %{
        "iss" => "https://shop.myshopify.com/admin",
        "dest" => "https://shop.myshopify.com",
        "aud" => ExShopifyApp.api_key(),
        "sub" => "42",
        "exp" => now + 60,
        "nbf" => now - 5,
        "iat" => now - 5,
        "jti" => "00000000-0000-0000-0000-000000000000",
        "sid" => "session"
      },
      overrides
    )
  end

  defp sign(claims) do
    jwk = JOSE.JWK.from_oct(ExShopifyApp.api_secret())
    {_, token} = jwk |> JOSE.JWT.sign(%{"alg" => "HS256"}, claims) |> JOSE.JWS.compact()
    token
  end

  defp verify(claims), do: claims |> sign() |> Token.decode_and_verify()

  test "accepts a valid session token" do
    assert {:ok, %{"dest" => "https://shop.myshopify.com"}} = verify(claims())

    assert {:ok, "shop.myshopify.com", _claims} =
             claims() |> sign() |> Token.resource_from_token()
  end

  test "rejects a token for another app" do
    assert {:error, :invalid_audience} = verify(claims(%{"aud" => "other-api-key"}))
    assert {:error, :invalid_audience} = verify(Map.delete(claims(), "aud"))
  end

  test "rejects a token whose iss and dest hostnames differ" do
    assert {:error, :invalid_issuer} =
             verify(claims(%{"iss" => "https://other.myshopify.com/admin"}))

    assert {:error, :invalid_issuer} = verify(Map.delete(claims(), "iss"))
    assert {:error, :invalid_issuer} = verify(Map.delete(claims(), "dest"))
  end

  test "rejects a token without exp or nbf" do
    assert {:error, :missing_exp} = verify(Map.delete(claims(), "exp"))
    assert {:error, :missing_nbf} = verify(Map.delete(claims(), "nbf"))
  end

  test "rejects an expired token" do
    assert {:error, :token_expired} =
             verify(claims(%{"exp" => System.system_time(:second) - 3600}))
  end
end
