defmodule ExShopifyApp.Plugs.Token do
  use Guardian.Plug.Pipeline,
    otp_app: :ex_shopify_app,
    module: ExShopifyApp.Token,
    error_handler: __MODULE__.ErrorHandler

  plug :set_header_from_params
  plug Guardian.Plug.VerifyHeader, scheme: "Bearer"
  plug Guardian.Plug.EnsureAuthenticated
  plug Guardian.Plug.LoadResource

  @doc "Sets an authorization header from the id_token in the params if it exists."
  def set_header_from_params(conn, _opts) do
    cond do
      Plug.Conn.get_req_header(conn, "authorization") != [] ->
        conn

      is_binary(conn.params["id_token"]) ->
        Plug.Conn.put_req_header(conn, "authorization", "Bearer #{conn.params["id_token"]}")

      true ->
        conn
    end
  end

  defmodule ErrorHandler do
    @behaviour Guardian.Plug.ErrorHandler

    @impl Guardian.Plug.ErrorHandler
    def auth_error(conn, {type, _reason}, _opts) do
      conn
      |> send_resp(:unauthorized, to_string(type))
      |> halt()
    end
  end
end
