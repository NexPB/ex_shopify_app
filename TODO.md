# TODO

Security findings from the review that #14 did not fix. The most severe come first.

## Encrypt stored tokens

`shopify_access_tokens.access_token` and `refresh_token` are plaintext columns. Anyone with read access to the database or its backups can use them to call the Admin API.

- [ ] Allow an encrypted Ecto type for both fields (for example `Cloak.Ecto.Binary`), or document how a host app adds one.
