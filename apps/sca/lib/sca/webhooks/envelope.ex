defmodule Sca.Webhooks.Envelope do
  @moduledoc """
  Turns a delivery into the exact bytes and headers that go to the merchant.

  Routing metadata — id, event, timestamp — stays in the clear so a receiver can
  dispatch without decrypting anything; the `data` object is what gets encrypted
  when the tenant configured a certificate.

  Every request is signed:

      X-SCA-Signature: t=1755500000,v1=<hex hmac-sha256 of "t.body">

  The timestamp is inside the signed string, so a captured call cannot be
  replayed later without the secret.
  """

  alias Sca.Models.Embed.TenantSettings
  alias Sca.Models.Tenant
  alias Sca.Models.WebhookDelivery
  alias Sca.Webhooks.Encryption

  @type headers() :: [{String.t(), String.t()}]

  @doc """
  Builds `{:ok, body, headers}` for a delivery, or `{:error, reason}` when the
  tenant's certificate cannot be used.
  """
  @spec build(WebhookDelivery.t(), Tenant.t(), DateTime.t()) ::
          {:ok, String.t(), headers()} | {:error, term()}
  def build(
        %WebhookDelivery{} = delivery,
        %Tenant{settings: %TenantSettings{} = settings},
        now \\ Timex.now()
      ) do
    with {:ok, data} <- encode_data(delivery, settings) do
      body =
        Jason.encode!(
          Map.merge(
            %{
              "id" => delivery.public_id,
              "event" => delivery.event,
              "created_at" => Timex.format!(delivery.inserted_at, "{RFC3339z}")
            },
            data
          )
        )

      {:ok, body, headers(delivery, settings, body, now)}
    end
  end

  @doc """
  The signature header value for a body, exposed so a receiver's implementation
  can be checked against ours in tests.
  """
  @spec signature(String.t(), String.t(), DateTime.t()) :: String.t()
  def signature(secret, body, %DateTime{} = timestamp) do
    unix = Timex.to_unix(timestamp)
    digest = :crypto.mac(:hmac, :sha256, secret, "#{unix}.#{body}") |> Base.encode16(case: :lower)

    "t=#{unix},v1=#{digest}"
  end

  defp encode_data(%WebhookDelivery{payload: payload}, %TenantSettings{webhook_certificate: nil}) do
    {:ok, %{"data" => payload}}
  end

  defp encode_data(%WebhookDelivery{payload: payload}, %TenantSettings{
         webhook_certificate: certificate
       }) do
    with {:ok, encrypted} <- Encryption.encrypt(Jason.encode!(payload), certificate) do
      {:ok, %{"encrypted" => encrypted}}
    end
  end

  defp headers(delivery, settings, body, now) do
    base = [
      {"content-type", "application/json"},
      {"user-agent", "sca-webhooks/1"},
      {"x-sca-event", delivery.event},
      {"x-sca-delivery", delivery.public_id}
    ]

    case settings.webhook_secret do
      secret when is_binary(secret) and secret != "" ->
        [{"x-sca-signature", signature(secret, body, now)} | base]

      _missing ->
        base
    end
  end
end
