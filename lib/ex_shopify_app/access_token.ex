defmodule ExShopifyApp.AccessToken do
  @moduledoc """
  Access token management.
  Docs: <https://shopify.dev/docs/apps/build/authentication-authorization/access-tokens/token-exchange#example>
  """

  import ExShopifyApp, only: [api_key: 0, api_secret: 0]

  @typep shop :: %{shopify_domain: String.t()}
  @typep token_type :: :offline | :online
  @typep token :: %{access_token: String.t(), scope: String.t()}

  @doc """
  Exchange a session token for an access token.
  """
  @spec fetch(shop(), String.t(), token_type()) :: {:ok, token()} | {:error, Tesla.Env.t()}
  def fetch(shop, session_token, type \\ :offline)
      when is_binary(session_token) and type in [:offline, :online] do
    shop
    |> client()
    |> Tesla.post("/oauth/access_token", %{
      client_id: api_key(),
      client_secret: api_secret(),
      grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
      subject_token: session_token,
      subject_token_type: "urn:ietf:params:oauth:token-type:id_token",
      requested_token_type: "urn:shopify:params:oauth:token-type:#{to_string(type)}-access-token"
    })
    |> then(fn
      {:ok, %Tesla.Env{status: 200} = resp} ->
        {:ok,
         %{
           access_token: Map.fetch!(resp.body, "access_token"),
           scope: Map.fetch!(resp.body, "scope")
         }}

      {:ok, %Tesla.Env{} = resp} ->
        {:error, resp}
    end)
  end

  @spec client(shop()) :: Tesla.Client.t()
  def client(%{shopify_domain: shopify_domain} = _shop) do
    host = String.trim_leading(shopify_domain, "https://")

    Tesla.client(
      [
        {Tesla.Middleware.BaseUrl, "https://#{host}/admin"},
        {Tesla.Middleware.JSON, engine: JSON}
      ],
      Application.get_env(:tesla, :adapter, Tesla.Adapter.Mint)
    )
  end
end
