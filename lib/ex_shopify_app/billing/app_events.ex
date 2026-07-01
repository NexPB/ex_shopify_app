defmodule ExShopifyApp.Billing.AppEvents do
  @moduledoc """
  Client for the Shopify App Events API, used to report usage events.

  Shopify maps each reported event to the meter configured on the app's pricing
  plans, keyed by `event_handle` (which must match a meter handle exactly). Some
  meters drive billing and others are tracking-only; this client is agnostic to that
  distinction — the host app decides which meter does what, and owns the
  idempotency-key strategy.

  Authentication uses the app's Dev Dashboard credentials
  (`ExShopifyApp.api_key/0` / `ExShopifyApp.api_secret/0`) via the
  `client_credentials` grant — see `fetch_token/0` for the raw request. The resulting
  JWT is valid ~60 min and cached by the supervised
  `ExShopifyApp.Billing.TokenServer` until shortly before it expires.

  Docs: <https://shopify.dev/docs/apps/build/app-events>
  """

  alias ExShopifyApp.Billing.TokenServer
  alias ExShopifyApp.HTTP

  @doc """
  Reports a usage event to Shopify.

    * `event_handle` - must match a usage meter handle from the pricing config.
    * `shop_gid` - the Shop GID, e.g. `"gid://shopify/Shop/123"` (see
      `ExShopifyApp.Graphql.ensure_gid/2`).
    * `value` - the usage amount (must be `> 0` to be billed).
    * `idempotency_key` - stable key deduping the event. Billing events are
      permanently deduped, so the key must be stable per billing period; the caller
      owns this.

  ## Options

    * `:timestamp` - the event `DateTime`, defaults to `DateTime.utc_now/0`.

  The API acknowledges receipt with `202` regardless of billing validation.
  Returns `{:ok, body}` on `202`, `{:error, %Tesla.Env{}}` on any other response, or
  `{:error, reason}` on a transport error.
  """
  @spec report(String.t(), String.t(), number(), String.t(), keyword()) ::
          {:ok, any()} | {:error, any()}
  def report(event_handle, shop_gid, value, idempotency_key, opts \\ []) do
    with {:ok, token} <- TokenServer.fetch() do
      timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())

      body = %{
        "shop_id" => shop_gid,
        "event_handle" => event_handle,
        "timestamp" => DateTime.to_iso8601(timestamp),
        "idempotency_key" => idempotency_key,
        "attributes" => %{"value" => value}
      }

      token
      |> client()
      # `unstable` is the only version the App Events API exposes as of now.
      |> Tesla.post("/app/unstable/events", body)
      |> HTTP.unwrap_response(202, fn env -> {:ok, env.body} end)
    end
  end

  @doc """
  Fetches a fresh App Events access token via the `client_credentials` grant.

  This is the raw primitive: it performs the token request and returns
  `{:ok, token, expires_in_seconds}` straight from Shopify, `{:error, %Tesla.Env{}}` on a
  non-200 (or a 200 without a token), or `{:error, reason}` on a transport error. It does
  no caching — for cached, serialized access use `ExShopifyApp.Billing.TokenServer`, which
  wraps this by default.
  """
  @spec fetch_token() :: {:ok, String.t(), non_neg_integer()} | {:error, any()}
  def fetch_token do
    body = %{
      "client_id" => ExShopifyApp.api_key(),
      "client_secret" => ExShopifyApp.api_secret(),
      "grant_type" => "client_credentials"
    }

    client()
    |> Tesla.post("/auth/access_token", body)
    |> HTTP.unwrap_response(fn
      %Tesla.Env{body: %{"access_token" => token} = resp} ->
        {:ok, token, Map.fetch!(resp, "expires_in")}

      %Tesla.Env{} = env ->
        {:error, env}
    end)
  end

  defp client(bearer_token \\ nil)

  defp client(bearer_token) when is_binary(bearer_token) do
    middleware =
      [
        {Tesla.Middleware.Headers, [{"authorization", "Bearer #{bearer_token}"}]}
        | http_middleware()
      ]

    Tesla.client(middleware, ExShopifyApp.tesla_adapter())
  end

  defp client(nil = _bearer_token) do
    Tesla.client(http_middleware(), ExShopifyApp.tesla_adapter())
  end

  defp http_middleware do
    [
      {Tesla.Middleware.BaseUrl, "https://api.shopify.com"},
      {Tesla.Middleware.JSON, engine: JSON}
    ]
  end
end
