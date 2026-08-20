defmodule Sca.Models.Embed.TenantSettings do
  @moduledoc """
  Per-tenant settings, stored as jsonb on the tenant row.

  They are always read as a whole, none of them is ever a query filter, and the
  list grows as the product does — so they live in one embedded document
  instead of a column each.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @default_request_timeout_seconds 300
  @min_request_timeout_seconds 30
  @max_request_timeout_seconds 3600

  @primary_key false
  embedded_schema do
    field :webhook_url, :string
    field :webhook_certificate, :string
    # HMAC key behind the X-SCA-Signature header.
    field :webhook_secret, :string, redact: true
    field :logo_url, :string
    field :default_request_timeout_seconds, :integer, default: @default_request_timeout_seconds
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [
      :webhook_url,
      :webhook_certificate,
      :webhook_secret,
      :logo_url,
      :default_request_timeout_seconds
    ])
    |> validate_required([:default_request_timeout_seconds])
    |> validate_url(:webhook_url)
    |> validate_url(:logo_url)
    |> validate_certificate(:webhook_certificate)
    |> validate_number(:default_request_timeout_seconds,
      greater_than_or_equal_to: @min_request_timeout_seconds,
      less_than_or_equal_to: @max_request_timeout_seconds
    )
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      case URI.new(value) do
        {:ok, %URI{scheme: scheme, host: host}}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []

        _other ->
          [{field, "must be an http(s) url"}]
      end
    end)
  end

  defp validate_certificate(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      if String.starts_with?(String.trim_leading(value), "-----BEGIN") do
        []
      else
        [{field, "must be PEM encoded"}]
      end
    end)
  end
end
