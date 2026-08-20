defmodule ScaApi.Fixtures do
  @moduledoc "A merchant with an API key, and a device that can actually sign."

  alias Sca.Actions
  alias Sca.Crypto

  def merchant do
    {:ok, %{tenant: tenant}} =
      Actions.Tenant.create(%{
        name: "Northstar Payments",
        owner_email: "ops-#{System.unique_integer([:positive])}@merchant.example.com"
      })

    {:ok, %{token: token}} = Actions.ApiToken.issue(tenant, %{name: "Tests"})

    %{tenant: tenant, api_token: token}
  end

  @doc "A bound device, with the private half kept so a test can sign like one."
  def device(tenant, external_id \\ "customer-1") do
    {public, private} = :crypto.generate_key(:ecdh, :secp256r1)
    {:ok, pending} = Actions.Binding.enroll(tenant, %{external_id: external_id})

    {:ok, session} =
      Actions.Binding.bind(pending.enroll_token, %{
        public_key: Base.encode64(public),
        name: "Dana's iPhone",
        push_platform: :ios
      })

    Map.put(session, :private_key, private)
  end

  @doc "Signs a decision the way the phone does."
  def sign_decision(device, request, decision) do
    request.id
    |> Crypto.signing_string(request.nonce, decision, request.payload_hash)
    |> sign(device)
  end

  @doc "Signs a refresh challenge."
  def sign_refresh(device, nonce) do
    device.binding.id
    |> Crypto.refresh_signing_string(nonce)
    |> sign(device)
  end

  defp sign(message, device) do
    :ecdsa
    |> :crypto.sign(:sha256, message, [device.private_key, :secp256r1])
    |> Base.encode64()
  end
end
