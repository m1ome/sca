defmodule ScaWeb.Enrollment do
  @moduledoc """
  The QR code a phone scans to bind itself.

  The payload is a contract with the installed mobile client: it reads the JSON,
  refuses anything without the `type` discriminator, and appends
  `/api/sca/v1/...` to `connect_url` for every later call. The merchant is part
  of that base URL, so a device carries it in every request it ever makes.

  The client also refuses a plain `http://` address in release builds, so the
  API host has to be configured for the QR to be usable outside development.
  """

  alias Sca.Models.Binding
  alias Sca.Models.Tenant

  @type_tag "sca-proto-enroll"

  @doc """
  The address this merchant's devices talk to — what the QR carries and what
  someone types in by hand when the camera will not cooperate.
  """
  @spec connect_url(Tenant.t()) :: String.t()
  def connect_url(%Tenant{} = tenant), do: "#{api_url()}/t/#{tenant.public_id}"

  @doc "The JSON the QR encodes."
  @spec payload(Tenant.t(), Binding.t()) :: String.t()
  def payload(%Tenant{} = tenant, %Binding{} = binding) do
    Jason.encode!(%{
      "type" => @type_tag,
      "connect_url" => connect_url(tenant),
      "connect_token" => binding.enroll_token,
      "nonce" => binding.enroll_nonce || ""
    })
  end

  @doc "That payload as an inline SVG, sized in pixels."
  @spec qr_code(Tenant.t(), Binding.t(), pos_integer()) :: String.t()
  def qr_code(%Tenant{} = tenant, %Binding{} = binding, size \\ 240) do
    tenant
    |> payload(binding)
    |> EQRCode.encode()
    |> EQRCode.svg(width: size, background_color: "#ffffff", color: "#0f172a")
    # The XML declaration belongs to a standalone file, not to inline markup.
    |> String.replace(~r/\A<\?xml[^>]*\?>\s*/, "")
  end

  # The device API is a different endpoint with its own host, and the console
  # has no code dependency on it — only the shared config. In dev that config
  # carries no `:url`, so the listening port is the fallback.
  defp api_url do
    config = Application.get_env(:sca_api, ScaApi.Endpoint, [])
    url = Keyword.get(config, :url, [])
    scheme = Keyword.get(url, :scheme, "http")
    host = Keyword.get(url, :host, "localhost")
    port = Keyword.get(url, :port) || config |> Keyword.get(:http, []) |> Keyword.get(:port)

    if is_nil(port) or port in [80, 443] do
      "#{scheme}://#{host}"
    else
      "#{scheme}://#{host}:#{port}"
    end
  end
end
