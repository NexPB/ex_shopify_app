defmodule ExShopifyApp.Web.CacheBodyReader do
  @moduledoc """
  Reads the body and puts the result in the `Conn`.
  """

  alias Plug.Conn

  # There's no max body size for webhooks, so we'll set a default of 10MB
  @ten_mb 10_485_760

  @doc """
  Read and "cache" the body.
  Store the body in the `assigns` under the `:raw_body` key.

  For a webhook, `:length` defaults to 10 MB; a `:length` given to `Plug.Parsers`
  overrides it. Returns `{:more, partial, conn}` without caching it when the body exceeds
  `:length`; `Plug.Parsers` then raises `Plug.Parsers.RequestTooLargeError` (413).
  """
  def read_body(%Conn{} = conn, opts) do
    if is_webhook_request?(conn) do
      # https://hexdocs.pm/plug/1.16.1/Plug.Parsers.html#module-custom-body-reader
      opts = Keyword.merge([length: @ten_mb], opts)

      with {:ok, body, conn} <- Plug.Conn.read_body(conn, opts) do
        conn = update_in(conn.assigns[:raw_body], &[body | &1 || []])
        {:ok, body, conn}
      end
    else
      Plug.Conn.read_body(conn, opts)
    end
  end

  defp is_webhook_request?(%Conn{} = conn) do
    case Conn.get_req_header(conn, "x-shopify-hmac-sha256") do
      [_hmac] -> true
      _ -> false
    end
  end
end
