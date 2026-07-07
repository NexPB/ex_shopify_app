defmodule ExShopifyApp.AccessToken.Heartbeat do
  @moduledoc """
  Periodically rotates token chains whose refresh token nears its 90-day expiry.

  On-demand refreshing only fires when a shop's token is actually used, so a
  dormant installation can silently cross the refresh-token cliff — after which
  only the merchant relaunching the app restores API access. This process asks
  the store for chains expiring inside `:window` (via
  `c:ExShopifyApp.AccessToken.Store.expiring_domains/2`) and rotates them through
  its lock-serialized `refresh_token/2`.

  Registered locally under `__MODULE__` by default, so one instance runs per
  node. Pass `{:global, __MODULE__}` (or any other name) via `:name` to run a
  single instance across the whole cluster instead — starting it on every node
  then leaves one live process and the rest get
  `{:error, {:already_started, pid}}`. Either way the work is idempotent: each
  refresh re-checks under the per-shop row lock, so any concurrent tick collapses
  into a single Shopify call per chain. Lifetime (non-expiring) rows carry no
  `refresh_token_expires_at` and are never selected.

  Add to your supervision tree:

      {ExShopifyApp.AccessToken.Heartbeat, store: MyApp.ShopifyAccessTokens}

  ## Options

    * `:store` (required) — module implementing `ExShopifyApp.AccessToken.Store`,
      including its optional `c:ExShopifyApp.AccessToken.Store.expiring_domains/2`
      callback
    * `:window` — seconds before refresh-token expiry to rotate (default 7 days)
    * `:interval` — milliseconds between scans (default 6 hours)
    * `:batch_limit` — max chains refreshed per batch, closest expiry first
      (default 500). When a tick fills its batch the remaining chains are drained
      on an immediate follow-up tick rather than idling until the next `:interval`.
    * `:max_concurrency` — chains rotated in parallel within a batch (default 10)
    * `:name` — process registration (default `__MODULE__`); pass
      `{:global, __MODULE__}` for a single cluster-wide instance, or `nil` to
      start an unregistered instance (used in tests)
  """

  use GenServer

  require Logger

  @default_window 7 * 24 * 60 * 60
  @default_interval :timer.hours(6)
  @default_batch_limit 500
  @default_max_concurrency 10

  @typedoc "See the module documentation for the available options."
  @type option ::
          {:store, module()}
          | {:window, pos_integer()}
          | {:interval, pos_integer()}
          | {:batch_limit, pos_integer()}
          | {:max_concurrency, pos_integer()}
          | {:name, GenServer.name() | nil}

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl GenServer
  def init(opts) do
    state = %{
      store: Keyword.fetch!(opts, :store),
      window: Keyword.get(opts, :window, @default_window),
      interval: Keyword.get(opts, :interval, @default_interval),
      batch_limit: Keyword.get(opts, :batch_limit, @default_batch_limit),
      max_concurrency: Keyword.get(opts, :max_concurrency, @default_max_concurrency)
    }

    {:ok, state, {:continue, :schedule}}
  end

  @impl GenServer
  def handle_continue(:schedule, state) do
    Process.send_after(self(), :tick, state.interval)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    domains = state.store.expiring_domains(state.window, limit: state.batch_limit)
    rotate_all(state, domains)

    if length(domains) >= state.batch_limit and domains != [] do
      send(self(), :tick)
      {:noreply, state}
    else
      {:noreply, state, {:continue, :schedule}}
    end
  end

  defp rotate_all(state, domains) do
    domains
    |> Task.async_stream(&rotate(state, &1),
      max_concurrency: state.max_concurrency,
      ordered: false,
      # Each refresh enforces its own lock/transaction timeouts; don't let the
      # stream kill a rotation mid-flight (its post-response commit is delicate).
      timeout: :infinity
    )
    |> Stream.run()
  end

  defp rotate(state, domain) do
    case state.store.refresh_token(%{shopify_domain: domain}) do
      {:ok, _token} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "ex_shopify_app heartbeat refresh failed for #{domain}: #{inspect(reason)}"
        )
    end
  end
end
