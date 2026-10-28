# Upgrading to 2.0

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
