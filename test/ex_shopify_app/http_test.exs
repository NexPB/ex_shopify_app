defmodule ExShopifyApp.HTTPTest do
  use ExUnit.Case, async: true

  alias ExShopifyApp.HTTP

  describe "unwrap_response/2,3" do
    test "applies the callback on the default 200 status" do
      result = {:ok, %Tesla.Env{status: 200, body: %{"ok" => true}}}

      assert {:ok, %{"ok" => true}} =
               HTTP.unwrap_response(result, fn env -> {:ok, env.body} end)
    end

    test "applies the callback on a custom success status" do
      result = {:ok, %Tesla.Env{status: 202, body: "accepted"}}

      assert {:ok, "accepted"} =
               HTTP.unwrap_response(result, 202, fn env -> {:ok, env.body} end)
    end

    test "lets the callback decide an error result" do
      result = {:ok, %Tesla.Env{status: 200, body: %{}}}

      assert {:error, :nope} =
               HTTP.unwrap_response(result, fn _env -> {:error, :nope} end)
    end

    test "returns {:error, env} on a non-success status" do
      result = {:ok, %Tesla.Env{status: 400, body: %{"error" => "bad"}}}

      assert {:error, %Tesla.Env{status: 400}} =
               HTTP.unwrap_response(result, fn _env -> {:ok, :unreached} end)
    end

    test "passes a transport error through" do
      assert {:error, :timeout} =
               HTTP.unwrap_response({:error, :timeout}, fn _env -> {:ok, :unreached} end)
    end
  end
end
