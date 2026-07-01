defmodule ExShopifyApp.Billing.Subscription do
  @moduledoc """
  Reads the merchant's active app subscription from the Shopify Admin API.

  This is the generic plumbing for "which plan is the merchant on?" — it returns the
  active subscription's `name`, `status`, and `current_period_end`. Mapping the plan
  name to allowances, prices, or upgrade rules is host-app *policy* and stays out of
  the library.

  The `current_period_end` is the end of the current billing cycle, useful for
  scoping a per-cycle idempotency key when reporting the billing meter (see
  `ExShopifyApp.Billing.AppEvents`).
  """

  alias ExShopifyApp.Graphql
  alias ExShopifyApp.Shop

  @typedoc "An active subscription summary."
  @type t :: %__MODULE__{
          name: String.t(),
          status: String.t(),
          current_period_end: String.t() | nil
        }

  @enforce_keys [:name, :status]
  defstruct [:name, :status, :current_period_end]

  @doc """
  Fetches the merchant's active Shopify subscription.

  Performs a network round-trip to the Admin GraphQL API; no special scope is required.

  Returns:

    * `{:ok, %Subscription{}}` when the merchant has an active subscription.
    * `{:error, :no_subscription}` when there is no active subscription (e.g. a
      development store with no paid plan).
    * `{:error, {:graphql, errors}}` when the API returns GraphQL errors on a 200.
    * `{:error, reason}` on a transport error or a non-200 response (the `Tesla.Env`).
  """
  @spec fetch_active(Shop.authorized()) :: {:ok, t()} | {:error, :no_subscription | term()}
  def fetch_active(%{shopify_domain: _, access_token: _} = shop) do
    shop
    |> Graphql.client()
    |> Graphql.query("""
    query {
      currentAppInstallation {
        activeSubscriptions {
          name
          status
          currentPeriodEnd
        }
      }
    }
    """)
    |> Graphql.unwrap(fn data ->
      with subscriptions when is_list(subscriptions) <-
             get_in(data, ["currentAppInstallation", "activeSubscriptions"]),
           %{"name" => name, "status" => status} = subscription <- List.first(subscriptions) do
        {:ok,
         %__MODULE__{
           name: name,
           status: status,
           current_period_end: Map.get(subscription, "currentPeriodEnd")
         }}
      else
        _ -> {:error, :no_subscription}
      end
    end)
  end
end
