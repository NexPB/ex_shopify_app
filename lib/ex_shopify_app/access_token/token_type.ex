defmodule ExShopifyApp.AccessToken.TokenType do
  @moduledoc """
  The Ecto type of `ExShopifyApp.AccessToken.Token`'s `:access_token` and `:refresh_token`.

  It delegates to the type set with
  `config :ex_shopify_app, ExShopifyApp.AccessToken.Token, token_type: type`, `:string`
  by default, and reads that config at runtime.
  """

  use Ecto.Type

  # A host type such as `Cloak.Ecto.Binary` is compiled after this library, so the
  # schema cannot name it in `field/3`; it is resolved on each call instead.
  defp impl do
    :ex_shopify_app
    |> Application.get_env(ExShopifyApp.AccessToken.Token, [])
    |> Keyword.get(:token_type, :string)
  end

  @impl true
  def type, do: Ecto.Type.type(impl())

  @impl true
  def cast(value), do: Ecto.Type.cast(impl(), value)

  @impl true
  def dump(value), do: Ecto.Type.dump(impl(), value)

  @impl true
  def load(value), do: Ecto.Type.load(impl(), value)

  @impl true
  def equal?(term1, term2), do: Ecto.Type.equal?(impl(), term1, term2)

  @impl true
  def embed_as(format), do: Ecto.Type.embed_as(impl(), format)
end
