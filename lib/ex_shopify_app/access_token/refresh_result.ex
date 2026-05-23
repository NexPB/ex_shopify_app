defmodule ExShopifyApp.AccessToken.RefreshResult do
  @moduledoc """
  Classifies and labels offline access-token refresh errors.

  This module keeps Shopify/Tesla-specific refresh error handling out of the repo-backed
  token store so `ExShopifyApp.AccessToken.Repo` can focus on persistence and locking.
  """

  @doc "Classify an error returned by the Shopify refresh request."
  def classify_error(%Tesla.Env{body: body} = env) do
    if match?(%{"error" => "invalid_grant"}, body) do
      :reauthorization_required
    else
      {:refresh_failed, env}
    end
  end

  def classify_error(reason), do: {:refresh_failed, reason}

  @doc "Return a compact, token-free label for operational refresh-error metadata."
  def error_label({:refresh_failed, %Tesla.Env{status: status}}),
    do: "refresh_failed:http_#{status}"

  def error_label({:refresh_failed, reason}),
    do: "refresh_failed:" <> String.slice(inspect(reason), 0, 200)

  @doc "Whether an exception represents a PostgreSQL row-lock timeout."
  def lock_timeout?(%{postgres: %{code: :lock_not_available}}), do: true
  def lock_timeout?(%{postgres: %{code: :lock_timeout}}), do: true
  def lock_timeout?(_), do: false
end
