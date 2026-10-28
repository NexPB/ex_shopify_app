defmodule ExShopifyApp.Plugs.AuthErrorHandler do
  @moduledoc """
  The Guardian error handler of `ExShopifyApp.Plugs.AdminAuth` and
  `ExShopifyApp.Plugs.ExtensionAuth`. Responds `401` with the error type as the body
  and halts.
  """
  @behaviour Guardian.Plug.ErrorHandler

  import Plug.Conn

  @impl Guardian.Plug.ErrorHandler
  def auth_error(conn, {type, _reason}, _opts) do
    conn
    |> send_resp(:unauthorized, to_string(type))
    |> halt()
  end
end
