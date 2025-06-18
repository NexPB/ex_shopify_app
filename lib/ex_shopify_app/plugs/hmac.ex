defmodule ExShopifyApp.Plugs.Hmac do
  @moduledoc """
  A plug to verify the HMAC of a request.
  """
  alias Plug.Conn

  import ExShopifyApp, only: [api_secret: 0]

  @typep hmac :: {:signature, String.t()} | {:header, String.t()}

  def init(opts) do
    opts
  end

  def call(%Conn{} = conn, _opts) do
    with {:ok, hmac_tuple} <- get_hmac(conn), true <- compare_hmac(conn, hmac_tuple) do
      conn
    else
      _ ->
        conn
        |> Conn.put_status(:unauthorized)
        |> Conn.send_resp(401, "Unauthorized")
        |> Conn.halt()
    end
  end

  @spec compare_hmac(Conn.t(), hmac()) :: boolean()
  defp compare_hmac(%Conn{} = conn, {_, hmac} = hmac_tuple) do
    compare_hmac = build_hmac(conn, hmac_tuple)
    Plug.Crypto.secure_compare(compare_hmac, hmac)
  end

  @spec build_hmac(Conn.t(), hmac()) :: String.t()
  defp build_hmac(%Conn{} = conn, {:signature, _hmac}) do
    query_string =
      conn.query_params
      |> Map.delete("signature")
      |> Enum.map(fn
        {key, value} when is_list(value) -> "#{key}=#{Enum.join(value, ",")}"
        {key, value} -> "#{key}=#{value}"
      end)
      |> Enum.sort()
      |> Enum.join()

    query_string
    |> hmac()
    |> Base.encode16(case: :lower)
  end

  defp build_hmac(%Conn{} = conn, {:header, _hmac}) do
    body = Map.fetch!(conn.assigns, :raw_body)

    body
    |> hmac()
    |> Base.encode64()
  end

  @spec get_hmac(Conn.t()) :: {:ok, hmac()} | {:error, :missing_hmac}
  defp get_hmac(%Conn{params: %{"signature" => hmac}}) do
    {:ok, {:signature, hmac}}
  end

  defp get_hmac(%Conn{} = conn) do
    case Conn.get_req_header(conn, "x-shopify-hmac-sha256") do
      [hmac] when is_binary(hmac) -> {:ok, {:header, hmac}}
      [] -> {:error, :missing_hmac}
    end
  end

  @spec hmac(String.t()) :: String.t()
  defp hmac(content) do
    :crypto.mac(:hmac, :sha256, api_secret(), content)
  end
end
