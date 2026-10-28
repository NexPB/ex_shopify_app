defmodule ExShopifyApp.KeyRotationTest do
  # Sets the :old_api_secret application env, which async tests read.
  use ExUnit.Case, async: false

  import Plug.Test

  alias ExShopifyApp.Plugs.Hmac
  alias Plug.Conn

  @old_secret "old-api-secret"
  @body ~s({"id":1})

  setup do
    Application.put_env(:ex_shopify_app, :old_api_secret, @old_secret)
    on_exit(fn -> Application.delete_env(:ex_shopify_app, :old_api_secret) end)
  end

  describe "ExShopifyApp.verifying_secrets/0" do
    test "lists the old secret after the current one" do
      assert ExShopifyApp.verifying_secrets() == ["test-api-secret", @old_secret]
    end

    test "omits an unset or empty old secret" do
      Application.delete_env(:ex_shopify_app, :old_api_secret)
      assert ExShopifyApp.verifying_secrets() == ["test-api-secret"]

      Application.put_env(:ex_shopify_app, :old_api_secret, "")
      assert ExShopifyApp.verifying_secrets() == ["test-api-secret"]
    end
  end

  describe "ExShopifyApp.Plugs.Hmac" do
    test "accepts a webhook signed with the old secret" do
      conn = @body |> webhook_conn(@old_secret) |> Hmac.call(Hmac.init(scheme: :webhook))

      refute conn.halted
    end

    test "rejects a webhook signed with another secret" do
      conn = @body |> webhook_conn("other-secret") |> Hmac.call(Hmac.init(scheme: :webhook))

      assert conn.halted
    end

    test "accepts an app proxy request signed with the old secret" do
      timestamp = System.system_time(:second)
      message = "shop=acme.myshopify.comtimestamp=#{timestamp}"

      signature =
        :hmac |> :crypto.mac(:sha256, @old_secret, message) |> Base.encode16(case: :lower)

      conn =
        :get
        |> conn("/proxy?shop=acme.myshopify.com&timestamp=#{timestamp}&signature=#{signature}")
        |> Hmac.call(Hmac.init(scheme: :app_proxy))

      refute conn.halted
    end
  end

  describe "ExShopifyApp.Token.verify/3" do
    test "accepts a session token signed with either secret" do
      assert {:ok, _claims} = ExShopifyApp.Token.verify(sign(claims(), "test-api-secret"))
      assert {:ok, _claims} = ExShopifyApp.Token.verify(sign(claims(), @old_secret))
    end

    test "rejects a session token signed with another secret" do
      assert {:error, :invalid_token} = ExShopifyApp.Token.verify(sign(claims(), "other"))
    end

    test "returns the claim error for a token the old secret signs" do
      expired = claims(%{"exp" => System.system_time(:second) - 3600})

      assert {:error, :token_expired} = ExShopifyApp.Token.verify(sign(expired, @old_secret))
    end
  end

  describe "ExShopifyApp.Plugs.Token" do
    test "authenticates a session token signed with the old secret" do
      conn =
        :get
        |> conn("/")
        |> Conn.put_req_header("authorization", "Bearer " <> sign(claims(), @old_secret))
        |> Conn.fetch_query_params()
        |> ExShopifyApp.Plugs.Token.call(ExShopifyApp.Plugs.Token.init([]))

      refute conn.halted
      assert ExShopifyApp.Token.Plug.current_resource(conn) == "shop.myshopify.com"
    end
  end

  defp webhook_conn(body, secret) do
    signature = :hmac |> :crypto.mac(:sha256, secret, body) |> Base.encode64()

    :post
    |> conn("/webhooks", body)
    |> Conn.put_req_header("x-shopify-hmac-sha256", signature)
    |> Conn.assign(:raw_body, [body])
  end

  defp claims(overrides \\ %{}) do
    now = System.system_time(:second)

    Map.merge(
      %{
        "iss" => "https://shop.myshopify.com/admin",
        "dest" => "https://shop.myshopify.com",
        "aud" => ExShopifyApp.api_key(),
        "exp" => now + 60,
        "nbf" => now - 5
      },
      overrides
    )
  end

  defp sign(claims, secret) do
    {_, token} =
      secret
      |> JOSE.JWK.from_oct()
      |> JOSE.JWT.sign(%{"alg" => "HS256"}, claims)
      |> JOSE.JWS.compact()

    token
  end
end
