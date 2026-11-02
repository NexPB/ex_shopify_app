defmodule ExShopifyApp.Plugs.Hmac do
  @moduledoc """
  A plug to verify that Shopify signed a request.

  Responds `401`, halts and logs a warning with the reason when the signature is
  missing or matches none of `ExShopifyApp.verifying_secrets/0`. On success it stores
  the verified scheme in `conn.private[:ex_shopify_app_hmac]`.

  ## Options

    * `:scheme` (required) - the signature the route accepts:
      * `:webhook` - the `x-shopify-hmac-sha256` header over the raw body, which
        `ExShopifyApp.Web.CacheBodyReader` must cache.
      * `:app_proxy` - the `signature` query parameter over the other query parameters.
        Read a verified parameter with `fetch_signed_param/2`.
    * `:max_age` - for `:app_proxy`, the maximum difference in seconds between the
      `timestamp` query parameter and now. Defaults to `300`.

  ## Example

      plug ExShopifyApp.Plugs.Hmac, scheme: :webhook

  """
  alias Plug.Conn

  import ExShopifyApp, only: [verifying_secrets: 0]

  require Logger

  @schemes [:webhook, :app_proxy]

  @type reason ::
          :missing_signature
          | :repeated_signature
          | :body_not_cached
          | :invalid_timestamp
          | :invalid_signature

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

    case verify(conn, scheme, opts) do
      :ok ->
        Conn.put_private(conn, :ex_shopify_app_hmac, scheme)

      {:error, reason} ->
        Logger.warning(
          "ex_shopify_app: Hmac rejected #{conn.method} #{conn.request_path} " <>
            "(scheme: #{scheme}): #{reason}",
          hmac_scheme: scheme,
          hmac_reason: reason
        )

        conn
        |> Conn.put_status(:unauthorized)
        |> Conn.send_resp(401, "Unauthorized")
        |> Conn.halt()
    end
  end

  @doc """
  Returns the scheme this plug verified the request with, or `nil` if it did not.

  ## Example

      iex> ExShopifyApp.Plugs.Hmac.verified_scheme(Plug.Test.conn(:get, "/proxy"))
      nil

  """
  @spec verified_scheme(Conn.t()) :: :webhook | :app_proxy | nil
  def verified_scheme(%Conn{} = conn), do: conn.private[:ex_shopify_app_hmac]

  @doc """
  Fetches a query parameter of a request this plug verified with `scheme: :app_proxy`.

  Returns `:error` when `key` is missing or repeated. Shopify sends
  `logged_in_customer_id` with an empty value when no customer is logged in.

  Raises `ArgumentError` when this plug did not verify the request with
  `scheme: :app_proxy`, or when `key` is `"signature"`. A plug that also runs on
  other routes checks `verified_scheme/1` first.

  ## Example

      plug ExShopifyApp.Plugs.Hmac, scheme: :app_proxy

      case Hmac.fetch_signed_param(conn, "logged_in_customer_id") do
        {:ok, id} when id != "" -> assign(conn, :customer_id, id)
        _ -> conn
      end

  """
  @spec fetch_signed_param(Conn.t(), String.t()) :: {:ok, String.t()} | :error
  def fetch_signed_param(%Conn{}, "signature") do
    raise ArgumentError, ~s(the app proxy signature does not sign the "signature" parameter)
  end

  def fetch_signed_param(%Conn{} = conn, key) when is_binary(key) do
    case verified_scheme(conn) do
      :app_proxy ->
        # Not `conn.params`: a body or path param overrides a query param there. Shopify
        # signs `a=1&a=2` as `a=1,2`, so neither value of a repeated key is signed alone.
        conn.query_string
        |> URI.query_decoder()
        |> Enum.filter(&(elem(&1, 0) == key))
        |> case do
          [{^key, value}] -> {:ok, value}
          _ -> :error
        end

      scheme ->
        raise ArgumentError,
              "fetch_signed_param/2 requires a request that ExShopifyApp.Plugs.Hmac " <>
                "verified with scheme: :app_proxy, got scheme: #{inspect(scheme)}"
    end
  end

  @spec verify(Conn.t(), :webhook | :app_proxy, keyword()) :: :ok | {:error, reason()}
  defp verify(%Conn{} = conn, :webhook, _opts) do
    case Conn.get_req_header(conn, "x-shopify-hmac-sha256") do
      [signature] ->
        case Map.fetch(conn.assigns, :raw_body) do
          {:ok, body} -> check(body, signature, &Base.encode64/1)
          # Plug.Parsers calls the body reader only for a content type that a parser
          # accepts, so a request without one never caches its body.
          :error -> {:error, :body_not_cached}
        end

      [] ->
        {:error, :missing_signature}

      _signatures ->
        {:error, :repeated_signature}
    end
  end

  defp verify(%Conn{} = conn, :app_proxy, opts) do
    # Shopify signs the raw query: a repeated key is joined with "," and a key such as
    # `a[b]` stays flat, so Plug's parsed `query_params` can't rebuild the message.
    params =
      conn.query_string
      |> URI.query_decoder()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    case Map.pop(params, "signature") do
      {[signature], params} ->
        if fresh?(params, Keyword.fetch!(opts, :max_age)) do
          params
          |> Enum.map(fn {key, values} -> "#{key}=#{Enum.join(values, ",")}" end)
          |> Enum.sort()
          |> Enum.join()
          |> check(signature, &Base.encode16(&1, case: :lower))
        else
          {:error, :invalid_timestamp}
        end

      {nil, _params} ->
        {:error, :missing_signature}

      {_signatures, _params} ->
        {:error, :repeated_signature}
    end
  end

  defp fresh?(%{"timestamp" => [timestamp]}, max_age) do
    case Integer.parse(timestamp) do
      {seconds, ""} -> abs(System.system_time(:second) - seconds) <= max_age
      _ -> false
    end
  end

  defp fresh?(_params, _max_age), do: false

  @spec check(iodata(), String.t(), (binary() -> String.t())) ::
          :ok | {:error, :invalid_signature}
  defp check(content, signature, encode) do
    signed? =
      Enum.any?(verifying_secrets(), fn secret ->
        :hmac
        |> :crypto.mac(:sha256, secret, content)
        |> encode.()
        |> Plug.Crypto.secure_compare(signature)
      end)

    if signed?, do: :ok, else: {:error, :invalid_signature}
  end
end
