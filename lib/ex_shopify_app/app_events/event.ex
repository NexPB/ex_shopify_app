defmodule ExShopifyApp.AppEvents.Event do
  @moduledoc """
  A usage event to report through `ExShopifyApp.AppEvents.report/2`.

    * `:event_handle` - must match a usage meter handle from the pricing config.
    * `:value` - the usage amount (must be `> 0` to be billed).
    * `:idempotency_key` - stable key deduping the event. Billing events are
      permanently deduped, so the key must be stable per billing period; the caller
      owns this.
    * `:timestamp` - the event `DateTime`. `new/2` stamps it with
      `DateTime.utc_now/0` when not given; on a struct built as a literal without
      one, `ExShopifyApp.AppEvents.report/2` stamps it at send time instead.
  """

  @enforce_keys [:event_handle, :value, :idempotency_key]
  defstruct [:event_handle, :value, :idempotency_key, :timestamp]

  @type t :: %__MODULE__{
          event_handle: String.t(),
          value: number(),
          idempotency_key: String.t(),
          timestamp: DateTime.t() | nil
        }

  @doc """
  Builds an event from a map of the required fields.

  ## Options

    * `:timestamp` - the event `DateTime`; defaults to `DateTime.utc_now/0`, so the
      event carries the time it was built rather than the time it is sent.
  """
  @spec new(
          %{
            required(:event_handle) => String.t(),
            required(:value) => number(),
            required(:idempotency_key) => String.t()
          },
          keyword()
        ) :: t()
  def new(%{event_handle: _, value: _, idempotency_key: _} = fields, opts \\ []) do
    timestamp = Keyword.get_lazy(opts, :timestamp, &DateTime.utc_now/0)
    struct!(__MODULE__, Map.put(fields, :timestamp, timestamp))
  end

  @doc """
  Maps the event to the App Events API request body for the shop identified by
  `shop_gid` (e.g. `"gid://shopify/Shop/123"`), stamping `DateTime.utc_now/0` when
  the event carries no timestamp.
  """
  @spec to_api_input(t(), String.t()) :: %{String.t() => term()}
  def to_api_input(%__MODULE__{} = event, shop_gid) when is_binary(shop_gid) do
    timestamp = event.timestamp || DateTime.utc_now()

    %{
      "shop_id" => shop_gid,
      "event_handle" => event.event_handle,
      "timestamp" => DateTime.to_iso8601(timestamp),
      "idempotency_key" => event.idempotency_key,
      "attributes" => %{"value" => event.value}
    }
  end
end
