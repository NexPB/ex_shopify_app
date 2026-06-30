defmodule ExShopifyApp.Billing do
  @moduledoc """
  Shopify-native billing plumbing.

  This is the library's billing entry point. It provides the reusable pieces of a
  Shopify App Pricing integration and leaves the per-app *policy* to the host:

    * `ExShopifyApp.Billing.AppEvents` - report metered usage to the App Events API.
    * `ExShopifyApp.Billing.Subscription` - read the merchant's active plan from the
      Admin API.
    * `pricing_url/2` - the merchant's hosted plan-selection page.

  ## Library vs host responsibilities

  The library does **not** model your plans. The plan catalog (allowances, prices,
  upgrade rules), what each meter counts, the meter handles, how usage is counted,
  the idempotency-key strategy, and scheduling all stay in the host app.

  Usage is reported against meters configured on the app's Shopify pricing plans,
  keyed by `event_handle` (which must match a meter handle exactly). Meters fall into
  two kinds, by convention:

    * **billing meters** - the reported value drives the merchant's metered charge.
      Shopify *sums* events within a billing cycle and permanently dedupes them on the
      idempotency key, so the key must be stable: a retry must reuse the same key to
      avoid double-charging. How you report is up to you — e.g. one unit per chargeable
      action keyed by that action's id, or a periodic total keyed to the billing cycle
      (e.g. the subscription's `current_period_end`). See `docs/BILLING.md`.
    * **tracking-only meters** - reported for visibility and not billed.

  Docs:
  - <https://shopify.dev/docs/apps/launch/billing/shopify-app-pricing>
  - <https://shopify.dev/docs/apps/build/app-events>
  """

  alias ExShopifyApp.Billing.Subscription
  alias ExShopifyApp.Shop

  @doc """
  Fetches the merchant's active Shopify subscription.
  """
  @spec fetch_active_subscription(Shop.authorized()) ::
          {:ok, Subscription.t()} | {:error, term()}
  defdelegate fetch_active_subscription(shop),
    to: Subscription,
    as: :fetch_active

  @doc """
  Builds the Shopify-hosted App Pricing page URL the merchant uses to choose or change
  plans.

  `app_handle` is the app's handle (e.g. `"my-app"`); `shop` carries the
  `:shopify_domain` the store handle is derived from.

  See <https://shopify.dev/docs/apps/launch/billing/shopify-app-pricing#plan-selection-page>.

  ## Examples

      iex> ExShopifyApp.Billing.pricing_url(%{shopify_domain: "acme.myshopify.com"}, "my-app")
      "https://admin.shopify.com/store/acme/charges/my-app/pricing_plans"

  """
  @spec pricing_url(Shop.t(), String.t()) :: String.t()
  def pricing_url(%{shopify_domain: shopify_domain}, app_handle)
      when is_binary(app_handle) do
    store_handle =
      shopify_domain
      |> Shop.normalize_domain()
      |> String.replace_suffix(".myshopify.com", "")

    "https://admin.shopify.com/store/#{store_handle}/charges/#{app_handle}/pricing_plans"
  end
end
