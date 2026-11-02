# Testing

`ExShopifyApp.Testing` signs session tokens, webhooks and app proxy queries the way
Shopify does. Your tests send these requests through the real plugs, so a test
covers the authentication of the route as well as its logic.

## Setup

The helpers sign with `ExShopifyApp.api_secret/0` and put `ExShopifyApp.api_key/0`
in the `aud` claim. Set both in the test config:

```elixir
# config/test.exs
config :ex_shopify_app,
  api_key: "test-api-key",
  api_secret: "test-api-secret"
```

Import the module in the `using` block of `MyAppWeb.ConnCase`:

```elixir
using do
  quote do
    import ExShopifyApp.Testing
    # ...
  end
end
```

`ExShopifyApp.Testing.shop_domain/0` returns a new `shop-N.myshopify.com` domain on
each call, so tests that run with `async: true` do not share a shop.

## App Home and admin extensions

`ExShopifyApp.Testing.admin_session_token/2` returns a token that passes
`ExShopifyApp.Plugs.AdminAuth`. Send it as a bearer token:

```elixir
test "renders the home page", %{conn: conn} do
  shop = shop_domain()

  conn =
    conn
    |> put_req_header("authorization", "Bearer " <> admin_session_token(shop))
    |> get("/home")

  assert html_response(conn, 200)
end
```

`ExShopifyApp.Testing.extension_session_token/2` returns a token for checkout and
customer account extensions, which passes `ExShopifyApp.Plugs.ExtensionAuth`.

Both tokens expire in 60 seconds. Use `:claims` to change or remove a claim. A `nil`
value removes the claim:

```elixir
admin_session_token(shop, claims: %{"exp" => System.system_time(:second) - 60})
admin_session_token(shop, claims: %{"sub" => "42"})
admin_session_token(shop, claims: %{"dest" => nil})
```

## Webhooks

`ExShopifyApp.Testing.put_webhook_headers/3` puts `content-type`,
`x-shopify-hmac-sha256` and, from the options, `x-shopify-shop-domain` and
`x-shopify-topic`. Send the same body that you signed:

```elixir
test "handles orders/create", %{conn: conn} do
  body = JSON.encode!(%{"id" => 1})

  conn =
    conn
    |> put_webhook_headers(body, shopify_domain: shop_domain(), topic: "orders/create")
    |> post("/webhooks", body)

  assert response(conn, 200)
end
```

`ExShopifyApp.Plugs.Hmac` verifies the raw body. Add the body reader to the
`Plug.Parsers` of your endpoint:

```elixir
body_reader: {ExShopifyApp.Web.CacheBodyReader, :read_body, []}
```

To build the headers yourself, use `ExShopifyApp.Testing.webhook_hmac/2`. It returns
only the signature.

## App proxy

`ExShopifyApp.Testing.app_proxy_query/3` returns a signed query string with `shop`,
`timestamp`, your params and `signature`:

```elixir
test "renders the proxy page for a customer", %{conn: conn} do
  query = app_proxy_query(shop_domain(), logged_in_customer_id: "1")

  conn = get(conn, "/proxy?" <> query)

  assert html_response(conn, 200)
end
```

A list value repeats its key and a map value encodes as `key[nested]=value`, as
Shopify sends them. Use `:timestamp` to test the `:max_age` option of
`ExShopifyApp.Plugs.Hmac`:

```elixir
app_proxy_query(shop, [], timestamp: System.system_time(:second) - 600)
```

## Rejected requests and secret rotation

Each signing helper accepts `:secret`. Sign with another secret to test that a
route rejects a forged request:

```elixir
conn
|> put_req_header("authorization", "Bearer " <> admin_session_token(shop, secret: "wrong"))
|> get("/home")
|> response(401)
```

To test the `:old_api_secret` config during a secret rotation, set it and sign with
the old secret. `Application.put_env/3` changes global state, so do not use it in
an `async: true` test:

```elixir
Application.put_env(:ex_shopify_app, :old_api_secret, "old-secret")
on_exit(fn -> Application.delete_env(:ex_shopify_app, :old_api_secret) end)

query = app_proxy_query(shop, [], secret: "old-secret")
```

## Plugs that run after authentication

To unit test a plug that runs after the authentication plugs, put the result of
those plugs on the conn instead of sending a signed request:

- `ExShopifyApp.Testing.put_session/2` puts a session token, its claims and its
  shop domain, as `ExShopifyApp.Plugs.AdminAuth` and
  `ExShopifyApp.Plugs.ExtensionAuth` do. It does not verify the token.
- `ExShopifyApp.Testing.put_hmac_verified/2` marks the conn as verified by
  `ExShopifyApp.Plugs.Hmac`.

```elixir
test "assigns the shop", %{conn: conn} do
  shop = shop_domain()
  opts = ExShopifyApp.Plugs.AssignShop.init(get_shop_by_domain: &%{domain: &1})

  conn =
    conn
    |> put_session(admin_session_token(shop))
    |> ExShopifyApp.Plugs.AssignShop.call(opts)

  assert conn.assigns.authenticated_shop == %{domain: shop}
end
```

## Access tokens

`ExShopifyApp.Testing.access_token/2` returns the `ExShopifyApp.AccessToken.Token`
that `ExShopifyApp.AccessToken.fetch/2` returns in `{:ok, token}`: a one-hour access
token and a 90-day refresh token. Store it to test code that calls
`c:ExShopifyApp.AccessToken.Store.valid_token/2`:

```elixir
shop = shop_domain()
:ok = MyApp.ShopifyAccessTokens.put_token(shop, access_token(shop, %{"scope" => "read_orders"}))
```

Set `"expires_in"`, `"refresh_token"` and `"refresh_token_expires_in"` to `nil` in
`body` for a token that does not expire.
