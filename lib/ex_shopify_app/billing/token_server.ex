defmodule ExShopifyApp.Billing.TokenServer do
  @moduledoc """
  Caches a Shopify Billing access token in a supervised GenServer.

  Generic to the Billing context: it serializes and caches whatever its `:fetcher`
  returns, applying an early-refresh skew so the token is never used at the edge of
  expiry. By default it caches the App Events `client_credentials` JWT via
  `ExShopifyApp.Billing.AppEvents.fetch_token/0`.

  Started automatically under `ExShopifyApp.Application`, so host apps need no setup.
  Because every request goes through this single process, concurrent first-callers
  coalesce onto one token fetch rather than each hitting the token endpoint — the
  refresh is serialized for free, with no global VM state.
  """
  use GenServer

  @typedoc """
  Fetches a fresh token, returning `{:ok, token, expires_in_seconds}` or
  `{:error, reason}`.
  """
  @type fetcher :: (-> {:ok, String.t(), non_neg_integer()} | {:error, any()})

  # Tokens are valid ~60 min; refresh a little early to avoid edge-of-expiry use.
  @token_skew_seconds 60

  # Generous call timeout so a slow token endpoint surfaces as `{:error, _}` from the
  # underlying request rather than a GenServer.call timeout exit.
  @call_timeout :timer.seconds(30)

  @doc """
  Starts the server.

  ## Options

    * `:name` - the registered name, defaults to `#{inspect(__MODULE__)}`.
    * `:fetcher` - a 0-arity `t:fetcher/0`, defaults to
      `&ExShopifyApp.Billing.AppEvents.fetch_token/0`.
  """
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns a valid cached token, fetching and caching a new one if needed.
  """
  @spec fetch(GenServer.server()) :: {:ok, String.t()} | {:error, any()}
  def fetch(server \\ __MODULE__) do
    GenServer.call(server, :fetch, @call_timeout)
  end

  @doc """
  Clears the cached token. Primarily useful for resetting state between tests.
  """
  @spec reset(GenServer.server()) :: :ok
  def reset(server \\ __MODULE__) do
    GenServer.call(server, :reset)
  end

  @impl true
  def init(opts) do
    fetcher = Keyword.get(opts, :fetcher, &ExShopifyApp.Billing.AppEvents.fetch_token/0)
    {:ok, %{fetcher: fetcher, token: nil}}
  end

  @impl true
  def handle_call(:fetch, _from, %{token: {token, %DateTime{} = expires_at}} = state) do
    if DateTime.before?(DateTime.utc_now(), expires_at) do
      {:reply, {:ok, token}, state}
    else
      refresh(state)
    end
  end

  def handle_call(:fetch, _from, %{token: nil} = state),
    do: refresh(state)

  def handle_call(:reset, _from, state),
    do: {:reply, :ok, %{state | token: nil}}

  defp refresh(%{fetcher: fetcher} = state) do
    case fetcher.() do
      {:ok, token, expires_in} ->
        expires_at = DateTime.add(DateTime.utc_now(), expires_in - @token_skew_seconds, :second)
        {:reply, {:ok, token}, %{state | token: {token, expires_at}}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
end
