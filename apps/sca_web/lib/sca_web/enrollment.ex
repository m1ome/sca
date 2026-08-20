defmodule ScaWeb.Enrollment do
  @moduledoc """
  The QR code a phone scans to bind itself.

  What goes into it is `Sca.Enrollment` — a contract with the mobile client.
  What is left here is where this deployment answers and how to draw it.
  """

  alias Sca.Enrollment
  alias Sca.Models.Binding
  alias Sca.Models.Tenant
  alias ScaUi.PublicUrl

  @doc "The address this merchant's devices talk to."
  @spec connect_url(Tenant.t()) :: String.t()
  def connect_url(%Tenant{} = tenant), do: Enrollment.connect_url(api_url(), tenant)

  @doc "The JSON the QR encodes."
  @spec payload(Tenant.t(), Binding.t()) :: String.t()
  def payload(%Tenant{} = tenant, %Binding{} = binding) do
    Enrollment.payload(api_url(), tenant, binding)
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
  # has no code dependency on it — only the shared config.
  defp api_url, do: PublicUrl.of(:sca_api, ScaApi.Endpoint)
end
