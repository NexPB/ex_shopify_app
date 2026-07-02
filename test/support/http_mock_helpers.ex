defmodule ExShopifyApp.HTTPMockHelpers do
  @moduledoc """
  Convenience helpers for driving the Tesla adapter Mox mock (`ExShopifyApp.HTTPMock`,
  wired in as the Tesla adapter in `config/test.exs`).

  Tests drive the same mock through two front-ends, and these helpers cut the
  `{:ok, %Tesla.Env{}}` boilerplate for both:

    * raw `Mox.stub/3` — `stub_http_json/2` sets a standing fixed response callable any
      number of times (including zero); `stub_http/1` takes a handler function for full
      control (multi-endpoint routing, per-request assertions, call counting, `flunk`).
    * `Tesla.Test.expect_tesla_call/1` — `expect_http_json/2` wraps the common
      fixed-response, expect-with-verification case, and `expect_http_call/3` adds a
      request-validating callback for tests that assert on the outgoing request.
  """

  import Mox, only: [stub: 3]
  import ExShopifyApp.TestHelpers, only: [json_response: 2]

  @mock ExShopifyApp.HTTPMock

  @doc """
  Stub the mock adapter with a raw `handler` for full control — when the fixed-response
  helpers are too coarse (multi-endpoint routing, per-request assertions, call counting,
  or `flunk`-ing a forbidden endpoint).

  `handler` receives the request `Tesla.Env` and must return the `Tesla.Adapter.call/2`
  result: `{:ok, %Tesla.Env{}}` (pair with `json_response/2`) or `{:error, reason}`.
  Callable any number of times. The adapter's `opts` are dropped; reach for `Mox.stub/3`
  directly if you need them.

      stub_http(fn
        %{url: "url1"} ->
          {:ok, json_response(%{"access_token" => "jwt"})}

        %{url: "url2", headers: headers} ->
          assert {"authorization", "Bearer jwt"} in headers
          {:ok, json_response(%{"accepted" => true}, status: 202)}
      end)
  """
  def stub_http(handler) when is_function(handler, 1) do
    stub(@mock, :call, fn env, _opts -> handler.(env) end)
  end

  @doc """
  Stub the mock adapter to return `body` encoded as a JSON `Tesla.Env` for every
  request. `opts` are passed to `json_response/2` (e.g. `status: 503`). Use for fixed
  responses — including error bodies — where the test does not assert the call count.
  """
  def stub_http_json(body, opts \\ []) do
    stub(@mock, :call, fn _env, _opts -> {:ok, json_response(body, opts)} end)
  end

  @doc """
  Set a `Tesla.Test` expectation that the adapter is called `:times` times (default 1)
  and returns `body` as a JSON `Tesla.Env`. Remaining `opts` are passed to
  `json_response/2` (e.g. `status: 400`). A thin wrapper over
  `Tesla.Test.expect_tesla_call/1` for the common fixed-response case.
  """
  def expect_http_json(body, opts \\ []) do
    {times, resp_opts} = Keyword.pop(opts, :times, 1)
    Tesla.Test.expect_tesla_call(times: times, returns: json_response(body, resp_opts))
  end

  @doc """
  Like `expect_http_json/2`, but runs `validate` against the request `Tesla.Env` first
  (make assertions on `:method`, `:url`, `:body`, ... inside it) before returning `body`
  as a JSON `Tesla.Env`. Use for tests that assert on the outgoing request.
  """
  def expect_http_call(validate, body, opts \\ []) when is_function(validate, 1) do
    {times, resp_opts} = Keyword.pop(opts, :times, 1)

    Tesla.Test.expect_tesla_call(
      times: times,
      returns: fn env, _opts ->
        validate.(env)
        {:ok, json_response(body, resp_opts)}
      end
    )
  end
end
