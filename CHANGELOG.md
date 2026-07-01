# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

(WIP)

## [1.2.0]

### Added

- Shopify-native billing plumbing (see `docs/BILLING.md`):
  - `ExShopifyApp.Billing.AppEvents`: report metered usage to the App Events API,
    authenticating via the `client_credentials` grant with a cached JWT.
  - `ExShopifyApp.Billing.Subscription`: read the merchant's active plan from the
    Admin API.
  - `ExShopifyApp.Graphql`: a minimal Admin GraphQL client plus
    `ensure_gid/2` / `trim_gid/1` helpers.
  - `ExShopifyApp.Billing` facade with `pricing_url/2` for the hosted plan-selection
    page.
- `ExShopifyApp.tesla_adapter/0`: single source of truth for the outbound Tesla
  adapter, now shared by the access-token and billing clients.

## [1.1.0]

### Added

- `ExShopifyApp.AccessToken.migrate/2` for migrating non-expiring offline tokens.
- `ExShopifyApp.AccessToken.Migrations` helper so host apps can run the bundled
  `shopify_access_tokens` migration without drift from the compiled schema.

### Changed

- Surface the exchanged-but-unpersisted token on persistence failure via
  `ExShopifyApp.AccessToken.PersistenceFailure`, so callers can retry the write
  instead of losing the token.

## [1.0.0]

### Added

- Expiring offline access tokens with safe refresh:
  - `ExShopifyApp.AccessToken.Repo` for generating a per-app durable store with
    `fetch_token/1`, `put_token/2`, `valid_token/2`, and `refresh_token/2`.
  - Per-shop, cross-node locked refresh via `SELECT ... FOR UPDATE`, never
    returning a refreshed token until the new refresh token is durably committed.
  - Telemetry events under `[:ex_shopify_app, :access_token, :refresh, ...]`.

## [0.1.1]

### Fixed

- Unset the `x-frame-options` header so the app can be embedded in the Shopify admin.

## [0.1.0]

### Added

- Initial release.

[Unreleased]: https://github.com/NexPB/ex_shopify_app/compare/1.2.0...HEAD
[1.2.0]: https://github.com/NexPB/ex_shopify_app/compare/1.1.0...1.2.0
[1.1.0]: https://github.com/NexPB/ex_shopify_app/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/NexPB/ex_shopify_app/compare/v0.1.1...1.0.0
[0.1.1]: https://github.com/NexPB/ex_shopify_app/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/NexPB/ex_shopify_app/releases/tag/v0.1.0
