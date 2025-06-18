defmodule ExShopifyApp.Plug do
  alias Plug.Conn

  @doc """
  Fetches the authenticated shop from the connection.

  ## Example

    iex> conn = %Plug.Conn{private: %{authenticated_shop: %{id: 1}}}
    iex> authenticated_shop(conn)
    %{id: 1}

    iex> authenticated_shop(%Plug.Conn{private: %{}})
    nil

  """
  @spec authenticated_shop(Conn.t()) :: map() | nil
  def authenticated_shop(%Conn{} = conn) do
    Map.get(conn.assigns, :authenticated_shop)
  end

  @doc """
  Like `authenticated_shop/1` but raises an error if no authenticated shop is set.
  """
  @spec authenticated_shop!(Conn.t()) :: map()
  def authenticated_shop!(%Conn{} = conn) do
    authenticated_shop(conn) || raise "Missing :authenticated_shop in Plug.Conn"
  end
end
