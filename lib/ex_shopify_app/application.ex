defmodule ExShopifyApp.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    app_events = ExShopifyApp.app_events_config()

    app_events_children =
      if app_events[:start_token_cache] do
        [app_events[:token_cache]]
      else
        []
      end

    children =
      [{Task.Supervisor, name: ExShopifyApp.AccessToken.TaskSupervisor} | app_events_children]

    Supervisor.start_link(
      children,
      strategy: :one_for_one,
      name: ExShopifyApp.Supervisor
    )
  end
end
