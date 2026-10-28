# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0-rc.1]

### Changed

- **Breaking:** `ExShopifyApp.Plugs.Token` is now `ExShopifyApp.Plugs.AdminAuth`, and
  `ExShopifyApp.Plugs.Token.ErrorHandler` is now `ExShopifyApp.Plugs.AuthErrorHandler`.

### Added

- `config :ex_shopify_app, old_api_secret: secret` or `SHOPIFY_OLD_API_SECRET` sets the
  client secret you rotate away from. `ExShopifyApp.Plugs.Hmac`,
  `ExShopifyApp.Plugs.AdminAuth`, `ExShopifyApp.Plugs.ExtensionAuth` and
  `ExShopifyApp.Token.verify/3` accept a signature from it or from `:api_secret`.
  Token exchange and refresh send only `:api_secret`.
- `ExShopifyApp.verifying_secrets/0` returns the secrets that verify an inbound signature.
- `ExShopifyApp.Token.verify/3` verifies a session token against each of
  `ExShopifyApp.verifying_secrets/0`. `decode_and_verify/3` uses only `:api_secret`.
- `ExShopifyApp.Plugs.VerifySessionToken`, which `ExShopifyApp.Plugs.AdminAuth` uses in
  place of `Guardian.Plug.VerifyHeader`.
- `ExShopifyApp.Plugs.ExtensionAuth` authenticates checkout and customer account UI
  extension session tokens. These tokens have no `iss`, and `dest` is the bare
  `{shop}.myshopify.com` hostname. `aud`, `dest`, `exp` and `nbf` are required.
- `ExShopifyApp.Plugs.AssignShop` with `type: :app_proxy` reads the `shop` query
  parameter of a request that `ExShopifyApp.Plugs.Hmac` verified with
  `scheme: :app_proxy`.
- `ExShopifyApp.Plugs.AssignShop` with `type: :flow_action` reads the `shopify_domain`
  body parameter of a Shopify Flow action that `ExShopifyApp.Plugs.Hmac` verified with
  `scheme: :webhook`. Flow actions send no `x-shopify-shop-domain` header.

## [2.0.0-rc.0]

### Changed

- **Breaking:** `ExShopifyApp.Plugs.Hmac` requires a `:scheme` option, `:webhook` or
  `:app_proxy`, and accepts only that signature. Before, any route accepted either
  one, so an app proxy signature, which does not sign the body, passed on a webhook
  route.
- **Breaking:** `ExShopifyApp.Plugs.AssignShop` with `type: :header` responds `401`
  unless `ExShopifyApp.Plugs.Hmac` verified the request with `scheme: :webhook`.
- `ExShopifyApp.AccessToken`, `ExShopifyApp.Graphql.client/2`, `api_uri/2` and
  `ExShopifyApp.Billing.pricing_url/2` raise `ArgumentError` unless the shop domain
  is a `{shop}.myshopify.com` hostname, so the client secret and access tokens are
  sent only to Shopify. `AssignShop` responds `401` for any other domain.

### Added

- `config :ex_shopify_app, ExShopifyApp.AccessToken.Token, token_type: type` sets
  the Ecto type of `access_token` and `refresh_token`, so a host app can encrypt
  them at rest. See the README.
- `ExShopifyApp.Shop.valid_domain?/1` and `validate_domain!/1`.
- `ExShopifyApp.Plugs.Hmac` rejects an app proxy request whose `timestamp` is more
  than `:max_age` seconds (default `300`) from now.

### Security

- The minimum versions are now `tesla` 1.18.3, `mint` 1.9.0, `plug` 1.19.3 and
  `guardian` 2.5.0. Older versions have published security advisories.
- `ExShopifyApp.Plugs.AllowIframe` now sets only the `frame-ancestors` directive
  and keeps the other directives of an existing `content-security-policy` header.
  Before, it replaced the header and dropped the host's policy, such as `script-src`.
- `ExShopifyApp.Token` now rejects a session token when `aud` is not
  `ExShopifyApp.api_key/0`, when the `iss` and `dest` hostnames differ, or when
  `exp` or `nbf` is absent. This also rejects checkout and customer account UI
  extension session tokens, which have no `iss`, and tokens from
  `ExShopifyApp.Token.encode_and_sign/3`, which have no `aud`.
- `ExShopifyApp.Graphql.client(shop, debug: true)` now passes
  `x-shopify-access-token` to the `:filter_headers` of `Tesla.Middleware.Logger`, in
  addition to the `:filter_headers` of the `:tesla` config. The logger runs before the
  header is set, so earlier versions did not log the token either.
- `ExShopifyApp.AppEvents.TokenServer` now redacts the cached token from crash
  reports and `:sys.get_status/1`.

### Fixed

- `ExShopifyApp.Web.CacheBodyReader` now responds 413 to a webhook body over
  `:length`. Before, it raised a `MatchError` and responded 500.
- `ExShopifyApp.Web.CacheBodyReader` now passes the `Plug.Parsers` options, such
  as `:length` and `:read_timeout`, to a non-webhook body read. Before, it dropped
  them and Plug's 8 MB default applied. A `application/x-www-form-urlencoded` body
  is now limited to the 1 MB default of `Plug.Parsers.URLENCODED`; give `:length` to
  `Plug.Parsers` to accept a larger one. Multipart uploads are not affected.
- `ExShopifyApp.Plugs.Hmac` verifies app proxy requests with a repeated or bracketed
  query key, such as `extra=1&extra=2`.

## [1.5.0]

### Added

- `ExShopifyApp.Storefront.client/2`: an authenticated Storefront API client that
  sends the shop's offline access token as a private Storefront token. Accepts
  `:api_version`, `:buyer_ip` and `:debug`.
- `ExShopifyApp.Storefront.query/3`: sends a Storefront GraphQL request; unwrap the
  result with `ExShopifyApp.Graphql.unwrap/2`.

## [1.4.3]

### Fixed

- `ExShopifyApp.AccessToken.Token`'s `:access_token` and `:refresh_token` are now
  redacted Ecto fields, so inspecting a token changeset no longer prints them. Before,
  only the struct hid them, and a failed write after a successful refresh returned
  `{:token_persistence_failed_after_refresh, %PersistenceFailure{}}` whose changeset
  `reason` printed both new tokens wherever the error was inspected or reported.

## [1.4.2]

### Fixed

- `ExShopifyApp.Shop.t/0`, `authorized/0` and `identified/0` now accept maps and
  structs with other keys. Before, Dialyzer reported that a call such as
  `valid_token/2` with a host shop struct can never return, and flagged every
  caller as unreachable.

## [1.4.1]

### Fixed

- A non-success response no longer carries the Tesla client in its
  `{:error, %Tesla.Env{}}` result, so inspecting the error no longer prints the
  `x-shopify-access-token` header.

## [1.4.0]

### Added

- `{:error, {:refresh_unavailable, reason}}`: the refresh task exited abnormally.

### Changed

- `refresh_token/2` and `migrate_token/2` now run their locked transaction in a
  supervised task rather than on the calling process, so it commits independently:
  a caller that rolls back, or dies, mid-refresh can no longer discard a token
  Shopify has already rotated. Refreshing from inside a caller transaction now logs
  a warning. Host apps need no supervision-tree change, and
  `ExShopifyApp.AccessToken.Store` is unchanged.

## [1.3.0]

### Added

- `ExShopifyApp.AccessToken.Heartbeat`: a supervision-tree GenServer that
  proactively rotates token chains nearing their 90-day refresh-token expiry,
  so dormant shops with no API activity don't silently lose access.
- `ExShopifyApp.AccessToken.Store.expiring_domains/2` (optional callback) and
  `ExShopifyApp.AccessToken.Repo.expiring_domains/3`: list chains expiring
  within a window, closest expiry first, to drive the heartbeat.

## [1.2.0]

### Added

- Shopify-native billing plumbing (see `docs/BILLING.md`):
  - `ExShopifyApp.AppEvents`: report metered usage to the App Events API,
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

[Unreleased]: https://github.com/NexPB/ex_shopify_app/compare/1.5.0...HEAD
[1.5.0]: https://github.com/NexPB/ex_shopify_app/compare/1.4.3...1.5.0
[1.4.3]: https://github.com/NexPB/ex_shopify_app/compare/1.4.2...1.4.3
[1.4.2]: https://github.com/NexPB/ex_shopify_app/compare/1.4.1...1.4.2
[1.4.1]: https://github.com/NexPB/ex_shopify_app/compare/1.4.0...1.4.1
[1.4.0]: https://github.com/NexPB/ex_shopify_app/compare/1.3.0...1.4.0
[1.3.0]: https://github.com/NexPB/ex_shopify_app/compare/1.2.0...1.3.0
[1.2.0]: https://github.com/NexPB/ex_shopify_app/compare/1.1.0...1.2.0
[1.1.0]: https://github.com/NexPB/ex_shopify_app/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/NexPB/ex_shopify_app/compare/v0.1.1...1.0.0
[0.1.1]: https://github.com/NexPB/ex_shopify_app/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/NexPB/ex_shopify_app/releases/tag/v0.1.0
