defmodule ExShopifyApp.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    app_events = ExShopifyApp.app_events_config()

    children =
      if app_events[:start_token_cache] do
        [app_events[:token_cache]]
      else
        []
      end

    Supervisor.start_link(
      children,
      strategy: :one_for_one,
      name: ExShopifyApp.Supervisor
    )
  end
end
