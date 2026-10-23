defmodule ExShopifyApp.Web.CacheBodyReaderTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias ExShopifyApp.Web.CacheBodyReader

  defp webhook(body) do
    conn(:post, "/webhooks", body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-shopify-hmac-sha256", "hmac")
  end

  defp parse(conn, opts \\ []) do
    opts =
      Plug.Parsers.init(
        [parsers: [:json], json_decoder: JSON, body_reader: {CacheBodyReader, :read_body, []}] ++
          opts
      )

    Plug.Parsers.call(conn, opts)
  end

  test "caches the raw webhook body" do
    conn = parse(webhook(~s({"id":1})))

    assert conn.body_params == %{"id" => 1}
    assert conn.assigns.raw_body == [~s({"id":1})]
  end

  test "raises RequestTooLargeError for a webhook body over the limit" do
    error =
      assert_raise Plug.Parsers.RequestTooLargeError, fn ->
        parse(webhook(~s({"id":1234567890})), length: 4)
      end

    assert Plug.Exception.status(error) == 413
  end

  test "applies the Plug.Parsers :length to a non-webhook body" do
    conn =
      conn(:post, "/", ~s({"id":1234567890}))
      |> put_req_header("content-type", "application/json")

    assert_raise Plug.Parsers.RequestTooLargeError, fn -> parse(conn, length: 4) end
  end
end
