defmodule ScaApi.JSON do
  @moduledoc """
  The wire shapes of both APIs.

  Written out field by field rather than derived from the schemas: these are
  contracts with a mobile app that is already in the field and with merchant
  code we do not control, so a new column must never appear in a response by
  accident.

  The device shapes match what the mobile client parses — `params` for the card
  fields, `payload_hash` for the hash over them, `connection_id` for a binding.

  Every `id` here is the row's UUID. Human-readable ids are for people reading
  a console, not for code holding a reference.
  """

  alias Sca.Models.Binding
  alias Sca.Models.Request

  @doc "An authorization, as the mobile client reads it."
  def authorization(%Request{} = request) do
    %{
      id: request.id,
      type: to_string(request.type),
      title: request.title,
      description: request.description,
      params: request.payload,
      payload_hash: request.payload_hash,
      nonce: request.nonce,
      status: to_string(request.status),
      signed_payload: request.signed_payload,
      signature: request.signature,
      algorithm: request.signature_algorithm,
      decided_at: timestamp(request.decided_at),
      created_at: timestamp(request.inserted_at),
      expires_at: timestamp(request.expires_at)
    }
  end

  @doc "What a device gets when it binds."
  def session(%{binding: binding, access_token: token, expires_at: expires_at}) do
    %{
      connection_id: binding.id,
      access_token: token,
      status: to_string(binding.status),
      access_token_expires_at: timestamp(expires_at)
    }
  end

  @doc "An approval, as a merchant reads it."
  def approval(%Request{} = request, %Binding{} = binding) do
    %{
      id: request.id,
      external_id: request.external_id,
      type: to_string(request.type),
      status: to_string(request.status),
      title: request.title,
      description: request.description,
      params: request.payload,
      payload_hash: request.payload_hash,
      binding: binding_summary(binding),
      created_at: timestamp(request.inserted_at),
      expires_at: timestamp(request.expires_at),
      decided_at: timestamp(request.decided_at),
      signature: request.signature,
      signed_payload: request.signed_payload,
      signature_algorithm: request.signature_algorithm
    }
  end

  @doc "A device, as a merchant reads it."
  def binding(%Binding{} = binding), do: binding_summary(binding)

  @doc """
  A device plus the code that activates it.

  The activation code is in this response and nowhere else — the QR the phone
  scans is built from it.
  """
  def enrollment(%Binding{} = binding) do
    binding
    |> binding_summary()
    |> Map.put(:activation, %{
      code: binding.enroll_token,
      nonce: binding.enroll_nonce,
      expires_at: timestamp(binding.enroll_expires_at)
    })
  end

  @doc "A list with its page, so a caller can walk it."
  def page(entries, %Flop.Meta{} = meta) do
    %{
      data: entries,
      page: %{
        current: meta.current_page,
        size: meta.page_size,
        total_pages: meta.total_pages,
        total_count: meta.total_count
      }
    }
  end

  @doc "An error, in the one shape both APIs use."
  def error(code, message, fields \\ nil) do
    %{error: %{code: code, message: message, fields: fields}}
  end

  defp binding_summary(%Binding{} = binding) do
    %{
      id: binding.id,
      external_id: binding.external_id,
      name: binding.name,
      status: to_string(binding.status),
      push_platform: binding.push_platform && to_string(binding.push_platform),
      attested: binding.attested,
      activated_at: timestamp(binding.activated_at),
      revoked_at: timestamp(binding.revoked_at),
      last_seen_at: timestamp(binding.last_seen_at)
    }
  end

  defp timestamp(nil), do: nil
  defp timestamp(datetime), do: Timex.format!(datetime, "{RFC3339z}")
end
