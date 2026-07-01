# Billing

`ex_shopify_app` ships the reusable plumbing for **Shopify-native billing**: report
metered usage through Shopify's [App Events API][app-events] and read the merchant's
active plan from the [Admin GraphQL API][admin-graphql]. It deliberately stops at the
plumbing; your app keeps the *policy*.

## Library vs host responsibilities

| Concern | Owner |
| --- | --- |
| Reporting usage events | **library** (`ExShopifyApp.Billing.AppEvents`) |
| Reading the active subscription | **library** (`ExShopifyApp.Billing.Subscription`) |
| Admin GraphQL client + GID helpers | **library** (`ExShopifyApp.Graphql`) |
| Hosted pricing-page URL | **library** (`ExShopifyApp.Billing.pricing_url/2`) |
| Plan catalog (allowances, prices, upgrade rules) | host app |
| What each meter counts & the meter handles | host app |
| Counting usage | host app |
| Idempotency-key strategy | host app |
| Scheduling (cron / Oban / …) | host app |

The library does **not** model your plans. Map a plan name to allowances or prices in
your own app.

## Shop reference

The billing functions take a shop carrying `:shopify_domain` and the offline
`:access_token`. The library's own `ExShopifyApp.AccessToken.Token` struct already has
both fields, so it can be passed directly; so can any map/struct exposing them:

```elixir
shop = %{shopify_domain: "acme.myshopify.com", access_token: "shpat_…"}
```

## Reporting usage

Usage is reported against the meters configured on your Shopify pricing plans, keyed by
`event_handle` (which must match a meter handle exactly). By convention meters are one
of two kinds:

- **Billing meter**: the reported value drives the metered charge. Shopify *sums* the
  events within a billing cycle, and permanently dedupes them on the `idempotency_key`,
  so the key must be stable: a retry must reuse the same key to avoid double-charging.
- **Tracking-only meter**: reported for visibility, never billed.

The most common pattern is to bill one unit per chargeable action, using that action's
own identifier as the idempotency key:

```elixir
alias ExShopifyApp.Billing.AppEvents
alias ExShopifyApp.Graphql

shop_gid = Graphql.ensure_gid(shop_id, "shop")

# Bill one unit each time the merchant processes an order. The order's GID is a
# naturally stable key, so a retry never double-charges; Shopify sums the events
# across the billing cycle.
AppEvents.report("orders_processed", shop_gid, 1, order_gid)
```

If instead you report a periodic *total* (rather than per-action increments), scope the
idempotency key to the billing cycle (e.g. the subscription's `current_period_end` from
`ExShopifyApp.Billing.Subscription.fetch_active/1`) so the event lands exactly once per
cycle.

`report/5` returns `{:ok, body}` on the API's `202` acknowledgement, or
`{:error, reason}`. Shopify acknowledges with `202` regardless of billing validation,
so a `value` of `0` is rejected upstream; skip the call when there's nothing to report.

Authentication is handled for you: the client uses your app's Dev Dashboard credentials
(`ExShopifyApp.api_key/0` / `api_secret/0`) via the `client_credentials` grant and
caches the resulting JWT in the supervised `ExShopifyApp.Billing.TokenServer`.

## Reading the active plan

```elixir
Subscription.fetch_active(shop)
#=> {:ok, %ExShopifyApp.Billing.Subscription{name: "Pro", status: "ACTIVE", current_period_end: "2026-07-28T00:00:00Z"}}
#=> {:error, :no_access_token}  # the shop has no usable token
#=> {:error, :no_subscription}  # no active plan (e.g. a development store)
#=> {:error, reason}            # transport error or non-200 response
```

## Sending the merchant to the pricing page

```elixir
Billing.pricing_url(shop, "my-app-handle")
#=> "https://admin.shopify.com/store/acme/charges/my-app-handle/pricing_plans"
```

Your app handle is explicit here, so store it in config and pass it in.

[app-events]: https://shopify.dev/docs/apps/build/app-events
[admin-graphql]: https://shopify.dev/docs/api/admin-graphql
