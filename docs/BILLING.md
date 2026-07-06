# Billing

`ex_shopify_app` ships the reusable plumbing for **Shopify-native billing**: report
metered usage through Shopify's [App Events API][app-events] and read the merchant's
active plan from the [Admin GraphQL API][admin-graphql]. It deliberately stops at the
plumbing; your app keeps the *policy*.

## Library vs host responsibilities

| Concern | Owner |
| --- | --- |
| Reporting usage events | **library** (`ExShopifyApp.AppEvents` — see [App Events](APP_EVENTS.md)) |
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

## Reporting metered usage

Metered charges are driven by **billing meters**, which are reported through the App
Events API via `ExShopifyApp.AppEvents` — the same client used for tracking-only
(analytics) meters. The how-to, the idempotency-key rules, and token-cache config live in
its own guide: **[App Events](APP_EVENTS.md)**.

The short version for billing: report against the meter configured on your pricing plan,
keyed by `event_handle`, with a *stable* idempotency key so retries never double-charge.
For a periodic total, scope that key to the billing cycle (e.g. the subscription's
`current_period_end` from `ExShopifyApp.Billing.Subscription.fetch_active/1`).

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
