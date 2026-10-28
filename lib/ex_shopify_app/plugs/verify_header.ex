defmodule ExShopifyApp.Plugs.VerifyHeader do
  @moduledoc """
  Verifies the `authorization: Bearer` session token with `ExShopifyApp.Token.verify/3`.

  Use it in place of `Guardian.Plug.VerifyHeader` inside a `Guardian.Plug.Pipeline`, so
  a token signed with any of `ExShopifyApp.verifying_secrets/0` passes. A request
  without the header passes through. An invalid token calls the pipeline's error
  handler with `{:invalid_token, reason}`. The options reach
  `ExShopifyApp.Token.verify_claims/2`.
  """
  import Plug.Conn

  alias Guardian.Plug.Pipeline

  def init(opts), do: opts

  def call(conn, opts) do
    with nil <- Guardian.Plug.current_token(conn, opts),
         {:ok, token} <- fetch_token(conn),
         {:ok, claims} <- ExShopifyApp.Token.verify(token, Keyword.get(opts, :claims, %{}), opts) do
      key = Pipeline.fetch_key(conn, opts)

      conn
      |> Guardian.Plug.put_current_token(token, key: key)
      |> Guardian.Plug.put_current_claims(claims, key: key)
    else
      {:error, reason} ->
        conn
        |> Pipeline.fetch_error_handler!(opts)
        |> apply(:auth_error, [conn, {:invalid_token, reason}, opts])
        |> Guardian.Plug.maybe_halt(opts)

      _ ->
        conn
    end
  end

  defp fetch_token(conn) do
    with [header] <- get_req_header(conn, "authorization"),
         [scheme, token] <- String.split(header, " ", parts: 2),
         "bearer" <- String.downcase(scheme) do
      {:ok, String.trim(token)}
    else
      _ -> :no_token_found
    end
  end
end
