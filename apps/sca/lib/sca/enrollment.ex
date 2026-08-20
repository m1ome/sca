defmodule Sca.Enrollment do
  @moduledoc """
  What a phone has to be told to bind itself.

  The payload is a contract with the installed mobile client: it reads this
  JSON out of a QR, refuses anything without the `type` discriminator, and then
  appends `/api/sca/v1/...` to `connect_url` for every later call. Changing a
  key here breaks scanning in the field, exactly like `Sca.Crypto`.

  The address itself is not the domain's business — each entry point knows how
  the world reaches it — so a caller passes its own base URL in.
  """

  alias Sca.Models.Binding
  alias Sca.Models.Tenant

  # The client checks this before it trusts anything else in the QR.
  @type_tag "sca-proto-enroll"

  @doc """
  Where this merchant's devices talk to us.

      iex> Sca.Enrollment.connect_url("https://api.example.com", %Sca.Models.Tenant{id: "abc"})
      "https://api.example.com/t/abc"
  """
  @spec connect_url(String.t(), Tenant.t()) :: String.t()
  def connect_url(base_url, %Tenant{} = tenant) do
    "#{String.trim_trailing(base_url, "/")}/t/#{tenant.id}"
  end

  @doc "The JSON a QR code carries, ready to encode."
  @spec payload(String.t(), Tenant.t(), Binding.t()) :: String.t()
  def payload(base_url, %Tenant{} = tenant, %Binding{} = binding) do
    Jason.encode!(%{
      "type" => @type_tag,
      "connect_url" => connect_url(base_url, tenant),
      "connect_token" => binding.enroll_token,
      "nonce" => binding.enroll_nonce || ""
    })
  end
end
