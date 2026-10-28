# Storefront API

`ex_shopify_app` ships a minimal server-side client for Shopify's
[Storefront GraphQL API][storefront]: `ExShopifyApp.Storefront`. It authenticates with
the shop's offline access token, sent as a [private Storefront access token][auth] in
the `Shopify-Storefront-Private-Token` header.

## Access scopes

Storefront queries need the app to hold the matching
[`unauthenticated_*` access scopes][scopes], for example
`unauthenticated_read_product_listings` to read products. Add them to the app's access
scopes and have the merchant approve them. Without them Shopify answers
`403 ACCESS_DENIED`.

## Querying

`client/2` takes the shop as any map carrying `:shopify_domain` and `:access_token`,
such as an `ExShopifyApp.AccessToken.Token`. Unwrap the result of `query/3` with
`ExShopifyApp.Graphql.unwrap/2`:

```elixir
alias ExShopifyApp.Graphql
alias ExShopifyApp.Storefront

shop = %{shopify_domain: "acme.myshopify.com", access_token: "shpat_…"}

shop
|> Storefront.client()
|> Storefront.query(
  """
  query Product($handle: String!) {
    product(handle: $handle) { id title }
  }
  """,
  %{handle: "red-shirt"}
)
|> Graphql.unwrap(fn data -> {:ok, data["product"]} end)
#=> {:ok, %{"id" => "gid://shopify/Product/1", "title" => "Red shirt"}}
#=> {:error, {:graphql, errors}}  # GraphQL errors in a 200 response
#=> {:error, %Tesla.Env{}}         # non-200 response, e.g. 403 ACCESS_DENIED
#=> {:error, reason}               # transport error
```

## Options

`client/2` accepts:

- `:api_version`: the Storefront API version. Defaults to `ExShopifyApp.api_version/0`.
- `:buyer_ip`: the buyer's IP address, sent as `Shopify-Storefront-Buyer-IP`. Pass it
  when the request acts on behalf of a buyer, so Shopify rate-limits and applies bot
  protection per buyer instead of per server. See [authentication][auth].
- `:debug`: when `true`, logs requests and responses. Defaults to `false`.

[storefront]: https://shopify.dev/docs/api/storefront
[auth]: https://shopify.dev/docs/api/storefront#authentication
[scopes]: https://shopify.dev/docs/apps/build/authentication-authorization/app-installation/manage-access-scopes
