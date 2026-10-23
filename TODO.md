# TODO

Security findings from the review that #14 did not fix. The most severe come first.

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
