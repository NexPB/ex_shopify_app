defmodule ExShopifyApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_shopify_app,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:plug, "~> 1.4"},
      {:guardian, "~> 2.0"},
      {:tesla, "~> 1.11"},
      {:mint, "~> 1.0", optional: true}
    ]
  end
end
