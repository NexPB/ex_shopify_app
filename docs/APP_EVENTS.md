# App Events

`ex_shopify_app` ships a client for Shopify's [App Events API][app-events]:
`ExShopifyApp.AppEvents`. It reports events keyed by `event_handle`, which Shopify maps
to a meter configured on your app. This is **not** billing-specific — meters come in two
kinds, and the same client serves both:

- **Billing meter**: the reported value drives the merchant's metered charge. Shopify
  *sums* the events within a billing cycle and permanently dedupes them on the
  `idempotency_key`, so the key must be stable: a retry must reuse the same key to avoid
  double-charging.
- **Tracking-only meter**: reported for visibility (analytics, usage insight) and never
  billed.

The client is agnostic to that distinction; the meter's configuration on the app decides
what an event does. See [docs/BILLING.md](BILLING.md) for how billing meters fit into a
Shopify App Pricing integration.

## Reporting an event

Events are reported against the meters configured on your app, keyed by `event_handle`
(which must match a meter handle exactly). The most common pattern is one event per
action, using that action's own identifier as the idempotency key:

```elixir
alias ExShopifyApp.AppEvents
alias ExShopifyApp.Graphql

shop = %{shop_gid: Graphql.ensure_gid(shop_id, "shop")}

# Report one event each time the merchant processes an order. The order's GID is a
# naturally stable key, so a retry never double-counts; for a billing meter Shopify
# sums the events across the billing cycle.
%{event_handle: "orders_processed", value: 1, idempotency_key: order_gid}
|> AppEvents.Event.new()
|> AppEvents.report(shop)
```

`report/2` takes the shop as any map carrying a `:shop_gid` — a bare map as above,
or your own shop schema if it exposes that field.

If instead you report a periodic *total* (rather than per-action increments) against a
billing meter, scope the idempotency key to the billing cycle (e.g. the subscription's
`current_period_end` from `ExShopifyApp.Billing.Subscription.fetch_active/1`) so the
event lands exactly once per cycle.

`report/2` returns `{:ok, body}` on the API's `202` acknowledgement, or
`{:error, reason}`. Shopify acknowledges with `202` regardless of validation, so a
`value` of `0` is rejected upstream; skip the call when there's nothing to report.

## Authentication

Authentication is handled for you: the client uses your app's Dev Dashboard credentials
(`ExShopifyApp.api_key/0` / `api_secret/0`) via the `client_credentials` grant and caches
the resulting JWT in the configured `ExShopifyApp.AppEvents.TokenCache`. The default
implementation, `ExShopifyApp.AppEvents.TokenServer`, is a supervised GenServer that
serializes refreshes so concurrent first-callers coalesce onto a single token fetch.

### Custom token cache

The token source is pluggable via the `:app_events` config group. Point `:token_cache`
at any module implementing the `ExShopifyApp.AppEvents.TokenCache` behaviour — for example
a Cachex/ETS TTL cache if you'd rather have non-blocking reads than serialized refreshes:

```elixir
config :ex_shopify_app, :app_events, token_cache: MyApp.TokenCache
```

By default the library auto-supervises the `:token_cache` module. If you start it yourself,
opt out:

```elixir
config :ex_shopify_app, :app_events, start_token_cache: false
```

[app-events]: https://shopify.dev/docs/apps/build/app-events
