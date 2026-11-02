defmodule ExShopifyApp.MixProject do
  use Mix.Project

  @version "2.1.0"
  @source_url "https://github.com/NexPB/ex_shopify_app"

  def project do
    [
      app: :ex_shopify_app,
      version: @version,
      source_url: @source_url,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ExShopifyApp.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:plug, ">= 1.19.3 and < 2.0.0"},
      {:guardian, ">= 2.5.0 and < 3.0.0"},
      {:jose, "~> 1.11"},
      {:tesla, ">= 1.18.3 and < 2.0.0"},
      {:telemetry, "~> 1.0"},
      {:ecto, "~> 3.0"},
      {:mint, ">= 1.9.0 and < 2.0.0", optional: true},
      # Optional: only needed for ExShopifyApp.AccessToken.Migrations — any host
      # running the bundled migration already has an Ecto SQL repo.
      {:ecto_sql, "~> 3.0", optional: true},
      {:postgrex, ">= 0.0.0", only: :test},
      {:mox, "~> 1.0", only: :test},
      {:ex_machina, "~> 2.7", only: :test}
    ]
  end

  defp description do
    "Your entrypoint to create a Shopify Application in Elixir."
  end

  defp docs do
    [
      main: "readme",
      source_ref: @version,
      extras: [
        "README.md",
        "docs/APP_EVENTS.md",
        "docs/BILLING.md",
        "docs/STOREFRONT.md",
        "docs/TESTING.md",
        "UPGRADE.md"
      ],
      groups_for_extras: [Guides: ~r{docs/}],
      groups_for_modules: [
        Plugs: ~r/^ExShopifyApp\.Plugs\./,
        "Access tokens": ~r/^ExShopifyApp\.AccessToken/,
        "App Events": ~r/^ExShopifyApp\.AppEvents/,
        Billing: ~r/^ExShopifyApp\.Billing/,
        Testing: [ExShopifyApp.Testing]
      ]
    ]
  end

  defp package() do
    [
      licenses: ["GPL-3.0"],
      links: %{
        "GitHub" => @source_url
      }
    ]
  end
end
