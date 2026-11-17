defmodule ExShopifyApp.AccessToken.PersistenceFailure do
  @moduledoc """
  Carries the token that Shopify issued but that could not be durably written.

  Returned inside `{:error, {:token_persistence_failed_after_refresh, %PersistenceFailure{}}}`
  by `ExShopifyApp.AccessToken.Repo.refresh_token/3` and `migrate_token/3` when the
  Shopify exchange succeeded but the durable write failed, and the retry stored no token.

  The stored row keeps the token it had, which Shopify still accepts, so the next
  refresh or migration recovers. Do not write `token` with `put_token/2`: it bypasses the
  row lock. `token` is the newest pair Shopify issued, and `reason` is the error from
  writing it.
  """

  alias ExShopifyApp.AccessToken.Token

  @typedoc "The exchanged-but-unpersisted token plus the underlying write error."
  @type t :: %__MODULE__{reason: term(), token: Token.t()}

  @enforce_keys [:reason, :token]
  defstruct [:reason, :token]
end
