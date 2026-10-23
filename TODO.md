# TODO

Security findings from the review that #14 did not fix. The most severe come first.

## Raise the dependency minimums

`mix.exs` allows versions with published advisories, and `mix.lock` pins them:

| Dependency | Locked | Fixed in | Advisories |
|---|---|---|---|
| `tesla` | 1.14.3 | 1.18.3 | [GHSA-9m9w-gxf7-rh8m], [GHSA-h74c-q9j7-mpcm], [GHSA-mc85-72gr-vm9f] (high); [GHSA-28jh-g32x-v9v4], [GHSA-q7jx-v53g-848w] (low) |
| `mint` | 1.7.1 | 1.9.0 | [GHSA-g586-ccqf-7x4r], [GHSA-2p26-p43x-fhp8] (high); [GHSA-mjqx-c6f6-7rc2] (moderate); [GHSA-2pg6-44cx-c49v] (low) |
| `plug` | 1.19.2 | 1.19.3 | [GHSA-j43x-5hjq-rgxf] (high) |

The library's own code doesn't use the affected Tesla features (redirects, decompression, dynamic schemes). Host apps still resolve these versions.

- [ ] Set `{:tesla, ">= 1.18.3 and < 2.0.0"}`, `{:mint, ">= 1.9.0 and < 2.0.0", optional: true}` and `{:plug, ">= 1.19.3 and < 2.0.0"}`.
- [ ] Run `mix deps.update tesla mint plug` and commit `mix.lock`.
- [ ] Add `mix hex.audit` to `.github/workflows/test.yml`.

## Keep the host's CSP in `AllowIframe`

`lib/ex_shopify_app/plugs/allow_iframe.ex:26` replaces the whole `content-security-policy` header, so it drops a policy (such as `script-src`) that the host set earlier in the pipeline.

- [ ] Replace only the `frame-ancestors` directive, or add it to the existing header.

## Check all session token claims

`lib/ex_shopify_app/token.ex` checks the signature, plus `exp` and `nbf` when the token has them. [Shopify's docs](https://shopify.dev/docs/apps/build/authentication-authorization/id-tokens) also require these checks:

- [ ] `aud` equals `ExShopifyApp.api_key/0`.
- [ ] The `iss` and `dest` hostnames are equal.
- [ ] `exp` and `nbf` are present. Guardian skips a claim that the token does not carry.

Override `verify_claims/2` in `ExShopifyApp.Token`; `api_key/0` is read at runtime, so a compile-time `claims:` option on the pipeline can't do it.

## Filter the access token from debug logs

`Graphql.client(shop, debug: true)` adds `Tesla.Middleware.Logger` (`lib/ex_shopify_app/graphql.ex:47`), which logs request headers at `debug` level, including `x-shopify-access-token`.

- [ ] Pass `filter_headers: ["x-shopify-access-token"]` to the logger.

## Keep the App Events token out of crash reports

`AppEvents.TokenServer` keeps the bearer JWT in its state. A crash report prints that state.

- [ ] Implement `format_status/1` and redact `:token`.

## Return 413 for a body over the limit in `CacheBodyReader`

`lib/ex_shopify_app/web/body_reader.ex:19` matches only `{:ok, body, conn}`. A webhook body over `:length` makes `Plug.Conn.read_body/2` return `{:more, _, conn}`, and the match raises, so the response is a 500, not a 413.

- [ ] Return `{:more, body, conn}` to `Plug.Parsers`, which raises `Plug.Parsers.RequestTooLargeError` (413).

## Encrypt stored tokens

`shopify_access_tokens.access_token` and `refresh_token` are plaintext columns. Anyone with read access to the database or its backups can use them to call the Admin API.

- [ ] Allow an encrypted Ecto type for both fields (for example `Cloak.Ecto.Binary`), or document how a host app adds one.

[GHSA-9m9w-gxf7-rh8m]: https://github.com/advisories/GHSA-9m9w-gxf7-rh8m
[GHSA-h74c-q9j7-mpcm]: https://github.com/advisories/GHSA-h74c-q9j7-mpcm
[GHSA-mc85-72gr-vm9f]: https://github.com/advisories/GHSA-mc85-72gr-vm9f
[GHSA-28jh-g32x-v9v4]: https://github.com/advisories/GHSA-28jh-g32x-v9v4
[GHSA-q7jx-v53g-848w]: https://github.com/advisories/GHSA-q7jx-v53g-848w
[GHSA-g586-ccqf-7x4r]: https://github.com/advisories/GHSA-g586-ccqf-7x4r
[GHSA-2p26-p43x-fhp8]: https://github.com/advisories/GHSA-2p26-p43x-fhp8
[GHSA-mjqx-c6f6-7rc2]: https://github.com/advisories/GHSA-mjqx-c6f6-7rc2
[GHSA-2pg6-44cx-c49v]: https://github.com/advisories/GHSA-2pg6-44cx-c49v
[GHSA-j43x-5hjq-rgxf]: https://github.com/advisories/GHSA-j43x-5hjq-rgxf
