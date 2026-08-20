defmodule Sca.Webhooks.Payload do
  @moduledoc """
  What a merchant sees in a webhook.

  Deliberately not "the schema as JSON": the wire shape is a contract with
  merchant code, so it is written out field by field here, and nothing added to
  a schema leaks into it by accident. Identifiers are the same uuids the API
  answers with, so a merchant can match a webhook to the call that caused it,
  plus their own `external_id`.

  Secrets never appear: no access tokens, no enrollment tokens, no public key.

  `sample/1` builds the same views out of made-up structs, for the test event a
  merchant fires from the console while wiring their receiver up.
  """

  alias Sca.Models.Binding
  alias Sca.Models.Request
  alias Sca.Repo

  @doc """
  The `data` object for whatever the event is about.

  The binding a request belongs to is loaded here rather than asked of the
  caller: an action should say *what happened*, not assemble the merchant's view
  of it.
  """
  @spec build(Request.t() | Binding.t()) :: map()
  def build(%Request{} = request) do
    %{binding: binding} = Repo.preload(request, :binding)

    %{"request" => request_view(request), "binding" => binding_view(binding)}
  end

  def build(%Binding{} = binding), do: %{"binding" => binding_view(binding)}

  @doc """
  What `event` looks like, with nothing behind it.

  Built from structs and run through the same views as a real event, so a sample
  cannot quietly drift from what a merchant will actually receive. The
  identifiers are fresh uuids naming nothing: a receiver tells a test apart by
  the `test` flag on the envelope, not by failing to look a payment up.
  """
  @spec sample(String.t()) :: map()
  def sample("binding." <> _rest = event) do
    %{"binding" => binding_view(sample_binding(event))}
  end

  def sample("request." <> _rest = event) do
    %{
      "request" => request_view(sample_request(event)),
      "binding" => binding_view(sample_binding("binding.activated"))
    }
  end

  @doc "Which kind of thing an event is about."
  @spec resource_type(Request.t() | Binding.t()) :: :request | :binding
  def resource_type(%Request{}), do: :request
  def resource_type(%Binding{}), do: :binding

  defp request_view(%Request{} = request) do
    %{
      "id" => request.id,
      "external_id" => request.external_id,
      "type" => to_string(request.type),
      "status" => to_string(request.status),
      "title" => request.title,
      "description" => request.description,
      "params" => request.payload,
      "payload_hash" => request.payload_hash,
      "created_at" => timestamp(request.inserted_at),
      "expires_at" => timestamp(request.expires_at),
      "decided_at" => timestamp(request.decided_at),
      # So a merchant can check the decision instead of taking our word.
      "signature" => request.signature,
      "signed_payload" => request.signed_payload,
      "signature_algorithm" => request.signature_algorithm
    }
  end

  defp binding_view(%Binding{} = binding) do
    %{
      "id" => binding.id,
      "external_id" => binding.external_id,
      "name" => binding.name,
      "status" => to_string(binding.status),
      "push_platform" => binding.push_platform && to_string(binding.push_platform),
      "attested" => binding.attested,
      "activated_at" => timestamp(binding.activated_at),
      "revoked_at" => timestamp(binding.revoked_at)
    }
  end

  # `request.created` is the one event whose name is not its status.
  defp sample_status("request.created"), do: :pending

  defp sample_status("request." <> status), do: String.to_existing_atom(status)

  defp sample_request(event) do
    now = Timex.now()
    status = sample_status(event)
    decided? = status in [:confirmed, :declined]

    %Request{
      id: Ecto.UUID.generate(),
      external_id: "sample-order-1",
      type: :payment,
      status: status,
      title: "Sample payment",
      description: "A test event from the SCA console. Nothing was charged.",
      payload: %{"amount" => "10.00", "currency" => "EUR", "beneficiary" => "ACME Ltd"},
      payload_hash: String.duplicate("0", 64),
      inserted_at: now,
      expires_at: Timex.shift(now, minutes: 5),
      decided_at: if(decided?, do: now),
      signature: if(decided?, do: "sample-signature"),
      signed_payload: if(decided?, do: "sample-signed-payload"),
      signature_algorithm: if(decided?, do: "ecdsa-p256")
    }
  end

  defp sample_binding(event) do
    now = Timex.now()
    revoked? = event == "binding.revoked"

    %Binding{
      id: Ecto.UUID.generate(),
      external_id: "sample-customer-1",
      name: "Sample device",
      status: if(revoked?, do: :revoked, else: :active),
      push_platform: :ios,
      attested: false,
      activated_at: now,
      revoked_at: if(revoked?, do: now)
    }
  end

  defp timestamp(nil), do: nil
  defp timestamp(%DateTime{} = datetime), do: Timex.format!(datetime, "{RFC3339z}")
end
