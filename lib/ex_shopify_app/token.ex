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

  # Checkout and customer account UI extension tokens put the bare hostname in `dest`.
  def resource_from_claims(%{"dest" => shopify_domain}) when is_binary(shopify_domain) do
    {:ok, shopify_domain}
  end

  def resource_from_claims(_claims) do
    {:error, :missing_shopify_domain}
  end

  @doc """
  Decodes and verifies a token like `decode_and_verify/3`, trying each of
  `ExShopifyApp.verifying_secrets/0` in turn.

  Returns the error for the last secret when none of them verifies the token.
  """
  @spec verify(Guardian.Token.token(), Guardian.Token.claims(), Guardian.options()) ::
          {:ok, Guardian.Token.claims()} | {:error, any()}
  def verify(token, claims_to_check \\ %{}, opts \\ []) do
    Enum.reduce_while(ExShopifyApp.verifying_secrets(), nil, fn secret, _error ->
      case decode_and_verify(token, claims_to_check, Keyword.put(opts, :secret, secret)) do
        # Guardian reports a signature made with another secret as :invalid_token.
        {:error, :invalid_token} = error -> {:cont, error}
        result -> {:halt, result}
      end
    end)
  end

  @doc """
  Checks the Shopify session token claims that Guardian does not check.

  Returns `{:error, :invalid_audience}` when `aud` is not `ExShopifyApp.api_key/0`,
  `{:error, :invalid_issuer}` when the `iss` and `dest` hostnames differ, and
  `{:error, :missing_exp}` or `{:error, :missing_nbf}` when the claim is absent.

  With `extension: true` in `options`, accepts a token without `iss`, as checkout and
  customer account UI extensions send, and returns `{:error, :missing_dest}` when `dest`
  is absent.
  """
  def verify_claims(claims, options) do
    with :ok <- verify_audience(claims),
         :ok <- verify_issuer(claims, Keyword.get(options, :extension, false)),
         :ok <- verify_present(claims, "exp", :missing_exp),
         :ok <- verify_present(claims, "nbf", :missing_nbf) do
      {:ok, claims}
    end
  end

  defp verify_audience(claims) do
    if claims["aud"] == ExShopifyApp.api_key(), do: :ok, else: {:error, :invalid_audience}
  end

  defp verify_issuer(%{"dest" => dest}, true = _extension) when is_binary(dest), do: :ok
  defp verify_issuer(_claims, true = _extension), do: {:error, :missing_dest}

  defp verify_issuer(%{"iss" => iss, "dest" => dest}, false = _extension)
       when is_binary(iss) and is_binary(dest) do
    case {URI.parse(iss), URI.parse(dest)} do
      {%URI{host: host}, %URI{host: host}} when is_binary(host) and host != "" -> :ok
      _ -> {:error, :invalid_issuer}
    end
  end

  defp verify_issuer(_claims, false = _extension), do: {:error, :invalid_issuer}

  # Guardian verifies `exp` and `nbf` before this callback runs, but accepts a token
  # that omits them.
  defp verify_present(claims, key, error) do
    if is_number(claims[key]), do: :ok, else: {:error, error}
  end
end
