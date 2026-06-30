defmodule ExShopifyApp.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ExShopifyApp.Billing.TokenServer
    ]

    Supervisor.start_link(
      children,
      strategy: :one_for_one,
      name: ExShopifyApp.Supervisor
    )
  end
end
