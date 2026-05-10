defmodule ExShopifyApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_shopify_app,
      version: "0.1.2",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:plug, "~> 1.4"},
      {:guardian, "~> 2.0"},
      {:tesla, "~> 1.11"},
      {:mint, "~> 1.0", optional: true}
    ]
  end

  defp description do
    "Your entrypoint to create a Shopify Application in Elixir."
  end

  defp package() do
    [
      licenses: ["GPL-3.0"],
      links: %{
        "GitHub" => "https://github.com/NexPB/ex_shopify_app"
      }
    ]
  end
end
