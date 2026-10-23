defmodule ExShopifyApp.AccessToken.TokenTypeTest do
  # async: false — the token type is global application config.
  use ExShopifyApp.RepoCase, async: false

  defmodule PrefixedType do
    use Ecto.Type

    def type, do: :string
    def cast(value) when is_binary(value), do: {:ok, value}
    def cast(_value), do: :error
    def dump(value) when is_binary(value), do: {:ok, "enc:" <> value}
    def dump(_value), do: :error
    def load("enc:" <> value), do: {:ok, value}
    def load(_value), do: :error
  end

  setup do
    previous = Application.get_env(:ex_shopify_app, Token)
    Application.put_env(:ex_shopify_app, Token, token_type: PrefixedType)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:ex_shopify_app, Token, previous),
        else: Application.delete_env(:ex_shopify_app, Token)
    end)
  end

  test "stores the tokens through the configured type" do
    domain = "shop.myshopify.com"

    :ok =
      TestStore.put_token(
        domain,
        build(:token, shopify_domain: domain, access_token: "shpat_x", refresh_token: "shprt_x")
      )

    assert %{rows: [["enc:shpat_x", "enc:shprt_x"]]} =
             TestRepo.query!(
               "SELECT access_token, refresh_token FROM shopify_access_tokens WHERE shopify_domain = $1",
               [domain]
             )

    assert %Token{access_token: "shpat_x", refresh_token: "shprt_x"} = stored(domain)
  end

  test "keeps a nil refresh token as NULL" do
    domain = "lifetime.myshopify.com"

    :ok = TestStore.put_token(domain, %Token{shopify_domain: domain, access_token: "shpat_x"})

    assert %{rows: [[nil]]} =
             TestRepo.query!(
               "SELECT refresh_token FROM shopify_access_tokens WHERE shopify_domain = $1",
               [domain]
             )

    assert %Token{refresh_token: nil} = stored(domain)
  end
end
