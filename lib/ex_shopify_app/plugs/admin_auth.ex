defmodule ExShopifyApp.Plugs.AdminAuth do
  @moduledoc """
  A Guardian pipeline that authenticates an App Home or admin UI extension session
  token, sent as `authorization: Bearer <token>` or as the `id_token` parameter.

  Requires `aud`, `iss`, `dest`, `exp` and `nbf`, with matching `iss` and `dest`
  hostnames. Responds `401` and halts otherwise.

  ## Example

      plug ExShopifyApp.Plugs.AdminAuth
      plug ExShopifyApp.Plugs.AssignShop, get_shop_by_domain: &MyApp.Shops.get_by_domain/1

  """
  use Guardian.Plug.Pipeline,
    otp_app: :ex_shopify_app,
    module: ExShopifyApp.Token,
    error_handler: ExShopifyApp.Plugs.AuthErrorHandler

  plug :set_header_from_params
  plug ExShopifyApp.Plugs.VerifySessionToken
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
end
