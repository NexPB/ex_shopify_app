defmodule ExShopifyApp.Token do
  use Guardian,
    otp_app: :ex_shopify_app,
    issuer: {Application, :get_env, [:ex_shopify_app, :app_name, "ex_shopify_app"]},
    secret_key: {ExShopifyApp, :api_secret, []},
    allowed_algos: ["HS512", "HS256"],
    allowed_drift: {Application, :get_env, [:ex_shopify_app, :allowed_drift, :timer.seconds(10)]}

  @doc "Sets the shopify domain as the subject for the token."
  def subject_for_token(%{shopify_domain: shopify_domain}, _claims)
      when is_binary(shopify_domain) do
    {:ok, shopify_domain}
  end

  def subject_for_token(_, _) do
    {:error, :invalid_shopify_domain}
  end

  @doc "Returns the shopify domain from the claims."
  def resource_from_claims(%{"dest" => "https://" <> shopify_domain}) do
    {:ok, shopify_domain}
  end

  def resource_from_claims(_claims) do
    {:error, :missing_shopify_domain}
  end
end
