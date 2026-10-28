defmodule ExShopifyApp.Plugs.ExtensionAuth do
  @moduledoc """
  A Guardian pipeline that authenticates a checkout or customer account UI extension
  session token sent as `authorization: Bearer <token>`.

  These tokens have no `iss`, and `dest` is the bare `{shop}.myshopify.com` hostname.
  `aud`, `dest`, `exp` and `nbf` are required. Responds `401` and halts otherwise.

  ## Example

      plug ExShopifyApp.Plugs.ExtensionAuth
      plug ExShopifyApp.Plugs.AssignShop, get_shop_by_domain: &MyApp.Shops.get_by_domain/1

  """
  use Guardian.Plug.Pipeline,
    otp_app: :ex_shopify_app,
    module: ExShopifyApp.Token,
    error_handler: ExShopifyApp.Plugs.AuthErrorHandler

  plug ExShopifyApp.Plugs.VerifySessionToken, extension: true
  plug Guardian.Plug.EnsureAuthenticated
  plug Guardian.Plug.LoadResource
end
