defmodule ExShopifyApp.Plugs.Hmac do
  @moduledoc """
  A plug to verify that Shopify signed a request.

  Responds `401` and halts when the signature is missing or invalid. On success it
  stores the verified scheme in `conn.private[:ex_shopify_app_hmac]`.

  ## Options

    * `:scheme` (required) - the signature the route accepts:
      * `:webhook` - the `x-shopify-hmac-sha256` header over the raw body, which
        `ExShopifyApp.Web.CacheBodyReader` must cache.
      * `:app_proxy` - the `signature` query parameter over the other query parameters.
    * `:max_age` - for `:app_proxy`, the maximum difference in seconds between the
      `timestamp` query parameter and now. Defaults to `300`.

  ## Example

      plug ExShopifyApp.Plugs.Hmac, scheme: :webhook

  """
  alias Plug.Conn

  import ExShopifyApp, only: [api_secret: 0]

  @schemes [:webhook, :app_proxy]

  def init(opts) do
    case Keyword.get(opts, :scheme) do
      scheme when scheme in @schemes ->
        Keyword.put_new(opts, :max_age, 300)

      scheme ->
        raise ArgumentError,
              "Plug requires a :scheme option, one of #{inspect(@schemes)}, " <>
                "got: #{inspect(scheme)}"
    end
  end

  def call(%Conn{} = conn, opts) do
    scheme = Keyword.fetch!(opts, :scheme)

    if verified?(conn, scheme, opts) do
      Conn.put_private(conn, :ex_shopify_app_hmac, scheme)
    else
      conn
      |> Conn.put_status(:unauthorized)
      |> Conn.send_resp(401, "Unauthorized")
      |> Conn.halt()
    end
  end

  @spec verified?(Conn.t(), :webhook | :app_proxy, keyword()) :: boolean()
  defp verified?(%Conn{} = conn, :webhook, _opts) do
    case Conn.get_req_header(conn, "x-shopify-hmac-sha256") do
      [signature] ->
        conn.assigns
        |> Map.fetch!(:raw_body)
        |> hmac()
        |> Base.encode64()
        |> Plug.Crypto.secure_compare(signature)

      _ ->
        false
    end
  end

  defp verified?(%Conn{} = conn, :app_proxy, opts) do
    # Shopify signs the raw query: a repeated key is joined with "," and a key such as
    # `a[b]` stays flat, so Plug's parsed `query_params` can't rebuild the message.
    params =
      conn.query_string
      |> URI.query_decoder()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    with {[signature], params} <- Map.pop(params, "signature"),
         true <- fresh?(params, Keyword.fetch!(opts, :max_age)) do
      params
      |> Enum.map(fn {key, values} -> "#{key}=#{Enum.join(values, ",")}" end)
      |> Enum.sort()
      |> Enum.join()
      |> hmac()
      |> Base.encode16(case: :lower)
      |> Plug.Crypto.secure_compare(signature)
    else
      _ -> false
    end
  end

  defp fresh?(%{"timestamp" => [timestamp]}, max_age) do
    case Integer.parse(timestamp) do
      {seconds, ""} -> abs(System.system_time(:second) - seconds) <= max_age
      _ -> false
    end
  end

  defp fresh?(_params, _max_age), do: false

  @spec hmac(iodata()) :: binary()
  defp hmac(content) do
    :crypto.mac(:hmac, :sha256, api_secret(), content)
  end
end
