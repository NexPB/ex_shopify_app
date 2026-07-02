defmodule ExShopifyApp.HTTPMockHelpers do
  @moduledoc """
  Convenience helpers for driving the Tesla adapter Mox mock (`ExShopifyApp.HTTPMock`,
  wired in as the Tesla adapter in `config/test.exs`).

  Tests drive the same mock through two front-ends, and these helpers cut the
  `{:ok, %Tesla.Env{}}` boilerplate for both:

    * raw `Mox.stub/3` — `stub_http_json/2` sets a standing fixed response callable any
      number of times (including zero).
    * `Tesla.Test.expect_tesla_call/1` — `expect_http_json/2` wraps the common
      fixed-response, expect-with-verification case.

  Tests that need bespoke behaviour (asserting on the request, counting calls) still
  reach for raw `Mox.stub`/`expect_tesla_call` directly.
  """

  import Mox, only: [stub: 3]
  import ExShopifyApp.TestHelpers, only: [json_response: 2]

  @mock ExShopifyApp.HTTPMock

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
end
