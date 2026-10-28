# Upgrading to 2.0

## Dependency minimums

2.0 requires `plug` 1.19.3, `guardian` 2.5.0, `tesla` 1.18.3 and, if you use it,
`mint` 1.9.0. Older versions have published security advisories. Update a lock file
that has an older version:

```sh
mix deps.update plug guardian tesla mint
```

## `ExShopifyApp.Plugs.Hmac` requires `:scheme`

Each route now accepts one signature. `init/1` raises `ArgumentError` without a
`:scheme` option.

```elixir
# 1.x
plug ExShopifyApp.Plugs.Hmac

# 2.0, webhook routes
plug ExShopifyApp.Plugs.Hmac, scheme: :webhook

# 2.0, app proxy routes
plug ExShopifyApp.Plugs.Hmac, scheme: :app_proxy
```

A route that receives both webhooks and app proxy requests must be split into two
pipelines.

`scheme: :app_proxy` responds `401` when the `timestamp` query parameter is missing
or more than 300 seconds from now. Set `:max_age` to change the limit:

```elixir
plug ExShopifyApp.Plugs.Hmac, scheme: :app_proxy, max_age: 600
```

## `ExShopifyApp.Plugs.AssignShop` with `type: :header` requires a verified webhook

`type: :header` responds `401` unless `ExShopifyApp.Plugs.Hmac` with
`scheme: :webhook` runs earlier in the same pipeline:

```elixir
plug ExShopifyApp.Plugs.Hmac, scheme: :webhook
plug ExShopifyApp.Plugs.AssignShop, type: :header, get_shop_by_domain: &MyApp.Shops.get_by_domain/1
```

## Shop domains must be `{shop}.myshopify.com`

These functions raise `ArgumentError` when the shop's domain is not a
`{shop}.myshopify.com` hostname, with or without a leading `https://`:

- `ExShopifyApp.AccessToken`
- `ExShopifyApp.Graphql.client/2` and `ExShopifyApp.Graphql.api_uri/2`
- `ExShopifyApp.Billing.pricing_url/2`

`ExShopifyApp.Plugs.AssignShop` responds `401` for any other domain.

A shop stored with a custom domain, such as `shop.example.com`, must store its
`{shop}.myshopify.com` domain instead. Use `ExShopifyApp.Shop.valid_domain?/1` to find
these records before you upgrade.

## Session tokens must have the app's `aud`, a matching `iss` and `dest`, `exp` and `nbf`

`ExShopifyApp.Token` rejects a session token when:

- `aud` is not `ExShopifyApp.api_key/0`: `{:error, :invalid_audience}`
- the `iss` and `dest` hostnames differ, or either is absent: `{:error, :invalid_issuer}`
- `exp` or `nbf` is absent: `{:error, :missing_exp}` or `{:error, :missing_nbf}`

Set `:api_key` or `SHOPIFY_API_KEY` to the app's client ID, the value Shopify puts in
`aud`.

These tokens are now rejected:

- Session tokens from checkout and customer account UI extensions, which have no `iss`.
  Authenticate them with `ExShopifyApp.Plugs.ExtensionToken` on a separate route:

  ```elixir
  plug ExShopifyApp.Plugs.ExtensionToken
  plug ExShopifyApp.Plugs.AssignShop, get_shop_by_domain: &MyApp.Shops.get_by_domain/1
  ```

- Tokens from `ExShopifyApp.Token.encode_and_sign/3`, which have no `aud`.

## Rotate the client secret with `:old_api_secret`

`ExShopifyApp.Plugs.Hmac`, `ExShopifyApp.Plugs.Token` and
`ExShopifyApp.Plugs.ExtensionToken` accept a signature from `:api_secret` or
`:old_api_secret`. To rotate the client secret, set `:api_secret` (or
`SHOPIFY_API_SECRET`) to the new secret and `:old_api_secret` (or
`SHOPIFY_OLD_API_SECRET`) to the old one. Remove `:old_api_secret` when Shopify signs
with the new secret only.

`ExShopifyApp.Token.decode_and_verify/3` checks `:api_secret` only. Call
`ExShopifyApp.Token.verify/3` to check both.

## `ExShopifyApp.Plugs.AssignShop` reads app proxy and Flow action shops

```elixir
# App proxy routes
plug ExShopifyApp.Plugs.Hmac, scheme: :app_proxy
plug ExShopifyApp.Plugs.AssignShop, type: :app_proxy, get_shop_by_domain: &MyApp.Shops.get_by_domain/1

# Shopify Flow action routes, after Plug.Parsers
plug ExShopifyApp.Plugs.Hmac, scheme: :webhook
plug ExShopifyApp.Plugs.AssignShop, type: :flow_action, get_shop_by_domain: &MyApp.Shops.get_by_domain/1
```

`type: :header` responds `401` for a Flow action, which has no
`x-shopify-shop-domain` header.

## `application/x-www-form-urlencoded` bodies are limited to 1 MB

`ExShopifyApp.Web.CacheBodyReader` now passes the `Plug.Parsers` options to a
non-webhook body read, so the 1 MB default of `Plug.Parsers.URLENCODED` applies to a
form body. 1.x applied Plug's 8 MB default. Give `:length` to accept a larger body:

```elixir
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  body_reader: {ExShopifyApp.Web.CacheBodyReader, :read_body, []},
  json_decoder: Jason,
  length: 8_000_000
```

`:length` also replaces the 10 MB default for webhook bodies.

## `ExShopifyApp.Plugs.AllowIframe` keeps the existing `content-security-policy`

`AllowIframe` now replaces only the `frame-ancestors` directive. 1.x replaced the whole
header. Directives that an earlier plug sets, such as `script-src`, now reach the
browser. Check that they allow the pages that the Shopify admin embeds.
