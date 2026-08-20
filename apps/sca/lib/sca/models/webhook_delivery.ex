defmodule Sca.Models.WebhookDelivery do
  @moduledoc """
  One attempt-tracked webhook call.

  A row exists from the moment an event happens until long after it was
  delivered: it is the answer to "did the merchant learn about this decision,
  and what did they reply". The body is stored in the clear even when the wire
  copy was encrypted for the merchant — otherwise support could never see what
  was sent.
  """

  use Sca.Schema, public_id: "WHK"

  @statuses ~w(pending delivered failed)a
  @resource_types ~w(request binding)a

  @required_fields ~w(event url status tenant_id)a
  @optional_fields ~w(resource_type resource_id payload encrypted test)a
  @all_fields @required_fields ++ @optional_fields

  @attempt_fields ~w(status attempts response_status response_body error duration_ms
                     last_attempt_at delivered_at)a

  @type t() :: %__MODULE__{}

  @derive {Flop.Schema,
           filterable: [:id, :public_id, :event, :status, :tenant_id, :resource_id, :test],
           sortable: [:inserted_at, :attempts],
           default_order: %{order_by: [:inserted_at], order_directions: [:desc]}}
  schema "webhook_deliveries" do
    public_id_field()

    field :event, :string
    field :resource_type, Ecto.Enum, values: @resource_types
    field :resource_id, Ecto.UUID

    field :url, :string
    field :payload, :map, default: %{}
    field :encrypted, :boolean, default: false
    # Sent from the console against a sample payload, not caused by anything.
    field :test, :boolean, default: false

    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :attempts, :integer, default: 0
    field :response_status, :integer
    field :response_body, :string
    field :error, :string
    field :duration_ms, :integer
    field :last_attempt_at, :utc_datetime_usec
    field :delivered_at, :utc_datetime_usec

    belongs_to :tenant, Sca.Models.Tenant

    timestamps()
  end

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, @all_fields)
    |> validate_required(@required_fields)
    |> assoc_constraint(:tenant)
  end

  @doc """
  Records one attempt: what came back, how long it took, and whether that
  settles the delivery.
  """
  def attempt_changeset(delivery, attrs) do
    delivery
    |> cast(attrs, @attempt_fields)
    |> validate_required([:status, :attempts])
    |> truncate_response_body()
  end

  # A merchant's error page can be a megabyte of HTML.
  @max_response_body 2_000

  defp truncate_response_body(changeset) do
    case get_change(changeset, :response_body) do
      body when is_binary(body) and byte_size(body) > @max_response_body ->
        put_change(changeset, :response_body, binary_part(body, 0, @max_response_body) <> "…")

      _other ->
        changeset
    end
  end
end
