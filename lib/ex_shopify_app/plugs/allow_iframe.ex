defmodule ExShopifyApp.Plugs.AllowIframe do
  @moduledoc """
  A plug to allow iframe requests from the Shopify admin.

  It sets the `frame-ancestors` directive of the `content-security-policy` response
  header and keeps the other directives that the header already has.
  """

  alias ExShopifyApp.Token
  alias Plug.Conn

  def init(opts) do
    opts
  end

  def call(%Conn{} = conn, _opts) do
    resource = Token.Plug.current_resource(conn)
    domains = ["https://admin.shopify.com"]

    domains =
      if is_binary(resource) do
        ["https://#{resource}"] ++ domains
      else
        domains
      end

    frame_ancestors = "frame-ancestors #{Enum.join(domains, " ")};"

    conn
    |> Plug.Conn.delete_resp_header("x-frame-options")
    |> Conn.update_resp_header(
      "content-security-policy",
      frame_ancestors,
      &put_frame_ancestors(&1, frame_ancestors)
    )
  end

  defp put_frame_ancestors(policy, frame_ancestors) do
    policy
    |> String.split(";")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or frame_ancestors?(&1)))
    |> Kernel.++([frame_ancestors])
    |> Enum.join("; ")
  end

  # Directive names are case-insensitive.
  defp frame_ancestors?(directive) do
    [name | _] = String.split(directive, ~r/\s+/, parts: 2)
    String.downcase(name) == "frame-ancestors"
  end
end
