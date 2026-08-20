defmodule Sca.Webhooks.Payload do
  @moduledoc """
  What a merchant sees in a webhook.

  Deliberately not "the schema as JSON": the wire shape is a contract with
  merchant code, so it is written out field by field here, and nothing added to
  a schema leaks into it by accident. Identifiers are the human-readable ones
  plus the merchant's own `external_id` — internal UUIDs are ours.

  Secrets never appear: no access tokens, no enrollment tokens, no public key.
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

  @doc "Which kind of thing an event is about."
  @spec resource_type(Request.t() | Binding.t()) :: :request | :binding
  def resource_type(%Request{}), do: :request
  def resource_type(%Binding{}), do: :binding

  defp request_view(%Request{} = request) do
    %{
      "id" => request.public_id,
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
      "id" => binding.public_id,
      "external_id" => binding.external_id,
      "name" => binding.name,
      "status" => to_string(binding.status),
      "push_platform" => binding.push_platform && to_string(binding.push_platform),
      "attested" => binding.attested,
      "activated_at" => timestamp(binding.activated_at),
      "revoked_at" => timestamp(binding.revoked_at)
    }
  end

  defp timestamp(nil), do: nil
  defp timestamp(%DateTime{} = datetime), do: Timex.format!(datetime, "{RFC3339z}")
end
