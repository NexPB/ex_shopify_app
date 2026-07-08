defmodule ExShopifyApp.HTTP do
  @moduledoc """
  Shared helpers for handling Tesla responses across the library's HTTP clients.
  """

  @doc """
  Unwraps a `Tesla.Env.result()` against an expected success `status`.

  On the expected success `status` (default `200`), `fun` is applied to the `Tesla.Env`
  and its result is returned — `fun` decides the final `{:ok, term} | {:error, term}`.
  Any other status collapses to `{:error, %Tesla.Env{}}`, and a transport error to
  `{:error, reason}`.
  """
  @spec unwrap_response(Tesla.Env.result(), pos_integer(), (Tesla.Env.t() -> result)) :: result
        when result: {:ok, term()} | {:error, term()}
  def unwrap_response(result, status \\ 200, fun)

  def unwrap_response({:ok, %Tesla.Env{status: status} = env}, status, fun)
      when is_function(fun, 1),
      do: fun.(env)

  def unwrap_response({:ok, %Tesla.Env{} = env}, _status, _fun),
    do: {:error, env}

  def unwrap_response({:error, reason}, _status, _fun),
    do: {:error, reason}
end
