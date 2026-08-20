defmodule Sca.Support.Device do
  @moduledoc """
  A stand-in for the phone: a P-256 key pair that can enroll, bind and sign the
  same strings the mobile client signs.

  Tests that "just need an active binding" get one that could actually approve
  a request, so a change in the signing contract fails here instead of in the
  field.
  """

  alias Sca.Actions
  alias Sca.Crypto

  @doc """
  Enrolls and binds a device for the tenant, returning everything a test needs
  to act as that device.
  """
  def bind(tenant, attrs \\ %{}) do
    {public, private} = :crypto.generate_key(:ecdh, :secp256r1)
    public_key = Base.encode64(public)

    external_id =
      Map.get(attrs, :external_id, "customer-#{System.unique_integer([:positive])}")

    {:ok, enrolled} = Actions.Binding.enroll(tenant, %{external_id: external_id})

    {:ok, session} =
      Actions.Binding.bind(enrolled.enroll_token, %{
        public_key: public_key,
        name: Map.get(attrs, :name, "iPhone"),
        device_info: %{"model" => "iPhone 15"},
        push_token: "push-#{System.unique_integer([:positive])}",
        push_platform: :ios
      })

    %{
      binding: session.binding,
      access_token: session.access_token,
      expires_at: session.expires_at,
      public_key: public_key,
      private_key: private
    }
  end

  @doc "Signs the decision string for a request, the way the client does."
  def decide(device, request, decision) when decision in ["confirm", "deny"] do
    request.id
    |> Crypto.signing_string(request.nonce, decision, request.payload_hash)
    |> sign(device)
  end

  @doc "Signs a refresh challenge with the device key (proof of possession)."
  def refresh_proof(device, nonce) do
    device.binding.id
    |> Crypto.refresh_signing_string(nonce)
    |> sign(device)
  end

  @doc "Signs an arbitrary message with the device key."
  def sign(message, device) do
    :ecdsa
    |> :crypto.sign(:sha256, message, [device.private_key, :secp256r1])
    |> Base.encode64()
  end
end
