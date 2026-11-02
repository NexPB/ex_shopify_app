defmodule ExShopifyApp.Testing do
  @moduledoc """
  Builds the signed requests and session tokens that Shopify sends, for the tests of
  an app that uses `ExShopifyApp`. See the [Testing guide](TESTING.md).

  Each helper signs with `ExShopifyApp.api_secret/0` and puts `ExShopifyApp.api_key/0`
  in the `aud` claim, so its output passes the matching plug:

  | Helper | Passes |
  | --- | --- |
  | `admin_session_token/2` | `ExShopifyApp.Plugs.AdminAuth` |
  | `extension_session_token/2` | `ExShopifyApp.Plugs.ExtensionAuth` |
  | `put_webhook_headers/3` | `ExShopifyApp.Plugs.Hmac` with `scheme: :webhook` |
  | `app_proxy_query/3` | `ExShopifyApp.Plugs.Hmac` with `scheme: :app_proxy` |

  Give `secret: secret` to sign with another secret, for example to test a rejected
  request or the `:old_api_secret` config.

  `put_session/2` and `put_hmac_verified/2` put on a conn what those plugs put on
  success, to unit test a plug that runs after them.
  """

  alias ExShopifyApp.AccessToken
  alias Plug.Conn

  @schemes [:webhook, :app_proxy]

  @doc """
  Returns a new `{shop}.myshopify.com` domain that `ExShopifyApp.Shop.valid_domain?/1`
  accepts.

  ## Examples

      iex> ExShopifyApp.Testing.shop_domain() =~ ~r/^shop-\\d+\\.myshopify\\.com$/
      true

  """
  @spec shop_domain() :: String.t()
  def shop_domain() do
    "shop-#{System.unique_integer([:positive])}.myshopify.com"
  end

  @doc """
  Returns an App Home or admin UI extension session token for `shopify_domain`, as
  Shopify signs it.

  The token expires in 60 seconds.

  ## Options

    * `:secret` - signs the token with this secret. Defaults to
      `ExShopifyApp.api_secret/0`.
    * `:claims` - a map merged over the default claims. A `nil` value removes the
      claim.

  ## Examples

      iex> token = ExShopifyApp.Testing.admin_session_token("acme.myshopify.com")
      iex> {:ok, claims} = ExShopifyApp.Token.verify(token)
      iex> {claims["iss"], claims["dest"]}
      {"https://acme.myshopify.com/admin", "https://acme.myshopify.com"}

  """
  @spec admin_session_token(String.t(), keyword()) :: String.t()
  def admin_session_token(shopify_domain, opts \\ []) when is_binary(shopify_domain) do
    %{"iss" => "https://#{shopify_domain}/admin", "dest" => "https://#{shopify_domain}"}
    |> session_token(opts)
  end

  @doc """
  Returns a checkout or customer account UI extension session token for
  `shopify_domain`, as Shopify signs it: without `iss`, and with the bare domain in
  `dest`.

  Takes the options of `admin_session_token/2`.

  ## Examples

      iex> token = ExShopifyApp.Testing.extension_session_token("acme.myshopify.com")
      iex> {:ok, claims} = ExShopifyApp.Token.verify(token, %{}, extension: true)
      iex> {claims["iss"], claims["dest"]}
      {nil, "acme.myshopify.com"}

  """
  @spec extension_session_token(String.t(), keyword()) :: String.t()
  def extension_session_token(shopify_domain, opts \\ []) when is_binary(shopify_domain) do
    session_token(%{"dest" => shopify_domain}, opts)
  end

  defp session_token(claims, opts) do
    now = System.system_time(:second)
    secret = Keyword.get_lazy(opts, :secret, &ExShopifyApp.api_secret/0)

    claims =
      %{
        "aud" => ExShopifyApp.api_key(),
        "exp" => now + 60,
        "nbf" => now - 5,
        "iat" => now - 5,
        "jti" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
      }
      |> Map.merge(claims)
      |> Map.merge(Keyword.get(opts, :claims, %{}))
      |> Map.reject(fn {_claim, value} -> is_nil(value) end)

    {_jws, token} =
      secret
      |> JOSE.JWK.from_oct()
      |> JOSE.JWT.sign(%{"alg" => "HS256"}, claims)
      |> JOSE.JWS.compact()

    token
  end

  @doc """
  Puts the session of `token` on `conn` as `ExShopifyApp.Plugs.AdminAuth` and
  `ExShopifyApp.Plugs.ExtensionAuth` put it: the token, its claims, and the shop
  domain as the resource.

  Does not verify `token`.

  ## Examples

      iex> conn =
      ...>   Plug.Test.conn(:get, "/")
      ...>   |> ExShopifyApp.Testing.put_session(
      ...>     ExShopifyApp.Testing.admin_session_token("acme.myshopify.com")
      ...>   )
      iex> ExShopifyApp.Token.Plug.current_resource(conn)
      "acme.myshopify.com"

  """
  @spec put_session(Conn.t(), String.t()) :: Conn.t()
  def put_session(%Conn{} = conn, token) when is_binary(token) do
    %{claims: claims} = ExShopifyApp.Token.peek(token)
    {:ok, shopify_domain} = ExShopifyApp.Token.resource_from_claims(claims)

    conn
    |> ExShopifyApp.Token.Plug.put_current_token(token)
    |> ExShopifyApp.Token.Plug.put_current_claims(claims)
    |> ExShopifyApp.Token.Plug.put_current_resource(shopify_domain)
  end

  @doc """
  Returns the base64 `x-shopify-hmac-sha256` signature of a webhook `body`.

  ## Options

    * `:secret` - signs with this secret. Defaults to `ExShopifyApp.api_secret/0`.

  ## Examples

      iex> ExShopifyApp.Testing.webhook_hmac(~s({"id":1}), secret: "secret")
      "A971iWIMgT8Zj9A9eWfikrFj7wQ16/Qwcc4OlRl2PLc="

  """
  @spec webhook_hmac(iodata(), keyword()) :: String.t()
  def webhook_hmac(body, opts \\ []) do
    secret = Keyword.get_lazy(opts, :secret, &ExShopifyApp.api_secret/0)

    :hmac
    |> :crypto.mac(:sha256, secret, body)
    |> Base.encode64()
  end

  @doc """
  Puts the headers of a Shopify webhook with `body` on `conn`: `content-type`,
  `x-shopify-hmac-sha256`, and the headers that the options set.

  Send `body` unchanged as the request body, through a `Plug.Parsers` that reads it
  with `ExShopifyApp.Web.CacheBodyReader`.

  ## Options

    * `:shopify_domain` - sets `x-shopify-shop-domain`, which
      `ExShopifyApp.Plugs.AssignShop` reads with `type: :header`.
    * `:topic` - sets `x-shopify-topic`.
    * `:secret` - signs with this secret. Defaults to `ExShopifyApp.api_secret/0`.

  ## Examples

      iex> conn =
      ...>   Plug.Test.conn(:post, "/webhooks")
      ...>   |> ExShopifyApp.Testing.put_webhook_headers("{}", shopify_domain: "acme.myshopify.com")
      iex> Plug.Conn.get_req_header(conn, "x-shopify-shop-domain")
      ["acme.myshopify.com"]

  """
  @spec put_webhook_headers(Conn.t(), iodata(), keyword()) :: Conn.t()
  def put_webhook_headers(%Conn{} = conn, body, opts \\ []) do
    headers =
      [
        {"content-type", "application/json"},
        {"x-shopify-hmac-sha256", webhook_hmac(body, opts)},
        {"x-shopify-shop-domain", opts[:shopify_domain]},
        {"x-shopify-topic", opts[:topic]}
      ]

    Enum.reduce(headers, conn, fn
      {_header, nil}, conn -> conn
      {header, value}, conn -> Conn.put_req_header(conn, header, value)
    end)
  end

  @doc """
  Returns the query string of an app proxy request to `shopify_domain`, with
  `shop`, `timestamp`, the `params` and a `signature` as Shopify signs it.

  `params` is a map or a list of pairs. A list value repeats its key, as Shopify sends
  `extra=1&extra=2`, and a map value encodes as `key[nested]=value`. Raises
  `ArgumentError` when `params` has a `shop`, `timestamp` or `signature` key.

  ## Options

    * `:timestamp` - the `timestamp` in Unix seconds. Defaults to now. `nil` leaves
      it out.
    * `:secret` - signs with this secret. Defaults to `ExShopifyApp.api_secret/0`.

  ## Examples

      iex> query =
      ...>   ExShopifyApp.Testing.app_proxy_query("acme.myshopify.com", [extra: [1, 2]],
      ...>     timestamp: 1_700_000_000,
      ...>     secret: "secret"
      ...>   )
      iex> query
      "shop=acme.myshopify.com&timestamp=1700000000&extra=1&extra=2&signature=ea3d0d03e4a27b0beeb2f249432cec2837d63bce154560b31c1d735f21c0701e"

  """
  @spec app_proxy_query(String.t(), Enumerable.t(), keyword()) :: String.t()
  def app_proxy_query(shopify_domain, params \\ [], opts \\ []) when is_binary(shopify_domain) do
    params = Enum.to_list(params)

    for {key, _value} <- params, to_string(key) in ~w(shop timestamp signature) do
      raise ArgumentError,
            "app_proxy_query/3 sets #{inspect(to_string(key))} itself, remove it from params"
    end

    timestamp = Keyword.get_lazy(opts, :timestamp, fn -> System.system_time(:second) end)

    base =
      if timestamp, do: [shop: shopify_domain, timestamp: timestamp], else: [shop: shopify_domain]

    query = URI.encode_query(flatten_params(base ++ params, nil))
    query <> "&" <> URI.encode_query(%{"signature" => app_proxy_signature(query, opts)})
  end

  defp flatten_params(params, parent) do
    Enum.flat_map(params, fn {key, value} ->
      key = if parent, do: "#{parent}[#{key}]", else: to_string(key)

      cond do
        is_map(value) -> flatten_params(value, key)
        is_list(value) -> Enum.map(value, &{key, to_string(&1)})
        true -> [{key, to_string(value)}]
      end
    end)
  end

  # Shopify signs the decoded pairs: a repeated key joined with ",", and a nested key
  # such as `a[b]` kept flat.
  defp app_proxy_signature(query, opts) do
    secret = Keyword.get_lazy(opts, :secret, &ExShopifyApp.api_secret/0)

    message =
      query
      |> URI.query_decoder()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn {key, values} -> "#{key}=#{Enum.join(values, ",")}" end)
      |> Enum.sort()
      |> Enum.join()

    :hmac
    |> :crypto.mac(:sha256, secret, message)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Marks `conn` as verified by `ExShopifyApp.Plugs.Hmac` with `scheme`, `:webhook`
  or `:app_proxy`.

  ## Examples

      iex> conn = ExShopifyApp.Testing.put_hmac_verified(Plug.Test.conn(:post, "/"), :webhook)
      iex> conn.private.ex_shopify_app_hmac
      :webhook

  """
  @spec put_hmac_verified(Conn.t(), :webhook | :app_proxy) :: Conn.t()
  def put_hmac_verified(%Conn{} = conn, scheme) when scheme in @schemes do
    Conn.put_private(conn, :ex_shopify_app_hmac, scheme)
  end

  @doc """
  Returns the `ExShopifyApp.AccessToken.Token` for an expiring offline token response
  from Shopify, as `ExShopifyApp.AccessToken.fetch/2` returns it.

  `body` is merged over a response with a one-hour access token and a 90-day refresh
  token. A `nil` value removes the field: remove `"expires_in"`, `"refresh_token"` and
  `"refresh_token_expires_in"` for a token that does not expire.

  ## Examples

      iex> token = ExShopifyApp.Testing.access_token("acme.myshopify.com", %{"scope" => "read_orders"})
      iex> {token.shopify_domain, token.scope, token.expires_in}
      {"acme.myshopify.com", "read_orders", 3600}

  """
  @spec access_token(String.t(), map()) :: AccessToken.Token.t()
  def access_token(shopify_domain, body \\ %{}) when is_binary(shopify_domain) do
    %{
      "access_token" => "shpat_" <> random_hex(),
      "refresh_token" => "shprt_" <> random_hex(),
      "scope" => "",
      "expires_in" => 3600,
      "refresh_token_expires_in" => 7_776_000
    }
    |> Map.merge(body)
    |> Map.reject(fn {_field, value} -> is_nil(value) end)
    |> AccessToken.Token.from_response(shopify_domain)
  end

  defp random_hex(), do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
end
