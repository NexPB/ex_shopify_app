defmodule ExShopifyApp.RecordingStore do
  @moduledoc """
  A store shim that behaves exactly like `ExShopifyApp.TestStore` but reports every
  `expiring_domains/2` scan it serves, so `ExShopifyApp.AccessToken.Heartbeat`'s batching
  can be asserted batch by batch instead of only through the resulting token state.

  Only the two callbacks the heartbeat calls are implemented. The scan runs inside the
  heartbeat's own process, so batches are reported through a registered name rather than
  `self()`: a test opts in with `record_batches/0` and then receives one
  `{:batch, opts, domains}` message per scan.
  """

  alias ExShopifyApp.TestStore

  @doc "Register the calling process as the recipient of this shim's batch messages."
  def record_batches, do: Process.register(self(), __MODULE__)

  @doc "Delegate to `TestStore`, reporting the scan's `opts` and result to the recorder."
  def expiring_domains(window, opts \\ []) do
    domains = TestStore.expiring_domains(window, opts)
    send(__MODULE__, {:batch, opts, domains})
    domains
  end

  defdelegate refresh_token(shop, opts \\ []), to: TestStore
end
