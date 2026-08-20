defmodule Sca.Models.Request do
  @moduledoc """
  An action the user has to approve or decline on their bound device.

  `payload` is what the device renders and hashes; `payload_hash` is the
  canonical hash the signature is built over. `external_id` is the merchant's
  idempotency key — retrying the same call must not put a second push on the
  phone.
  """

  use Sca.Schema, public_id: "REQ"

  alias Sca.Crypto
  alias Sca.Models.Request.Params

  @types ~w(payment login freeform)a
  @statuses ~w(pending confirmed declined expired cancelled)a
  @decisions ~w(confirmed declined)a

  @max_title_length 140
  @max_description_length 500

  @required_fields ~w(type title nonce status expires_at tenant_id binding_id)a
  @optional_fields ~w(external_id description payload)a
  @all_fields @required_fields ++ @optional_fields

  @decision_fields ~w(signed_payload signature signature_algorithm)a

  @type t() :: %__MODULE__{}
  @type status() :: :pending | :confirmed | :declined | :expired | :cancelled

  @derive {Flop.Schema,
           filterable: [:public_id, :external_id, :type, :status, :tenant_id, :binding_id],
           sortable: [:inserted_at, :expires_at],
           default_order: %{order_by: [:inserted_at], order_directions: [:desc]}}

  schema "requests" do
    public_id_field()

    # The merchant's own reference for whatever they are asking about. Unique
    # per tenant, which is what makes a retried call answer with this same card
    # instead of raising a second one.
    field :external_id, :string
    field :type, Ecto.Enum, values: @types
    field :title, :string
    field :description, :string, default: ""
    field :payload, :map, default: %{}
    field :payload_hash, :string
    field :nonce, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending

    field :signed_payload, :string
    field :signature, :string
    field :signature_algorithm, :string

    field :decided_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec

    belongs_to :tenant, Sca.Models.Tenant
    belongs_to :binding, Sca.Models.Binding

    timestamps()
  end

  def changeset(request, attrs) do
    request
    |> cast(attrs, @all_fields)
    |> validate_required(@required_fields)
    |> validate_length(:title, min: 1, max: @max_title_length)
    |> validate_length(:description, max: @max_description_length)
    |> put_params()
    |> assoc_constraint(:tenant)
    |> assoc_constraint(:binding)
    |> unique_constraint(:external_id, name: :requests_tenant_id_external_id_index)
  end

  @doc """
  Changeset recording the device's decision together with its signature.
  """
  def decision_changeset(request, decision, attrs) when decision in @decisions do
    request
    |> cast(attrs, @decision_fields)
    |> put_change(:status, decision)
    |> put_change(:decided_at, Timex.now())
    |> validate_required(@decision_fields)
  end

  @doc "Whether the request can still be answered."
  def pending?(%__MODULE__{status: :pending, expires_at: expires_at}) do
    Timex.after?(expires_at, Timex.now())
  end

  def pending?(%__MODULE__{}), do: false

  # Ours, never the caller's: a merchant able to set the hash could ask the user
  # to sign something other than what the card shows.
  defp put_params(changeset) do
    type = get_field(changeset, :type)
    params = Params.normalize(get_field(changeset, :payload) || %{})
    changeset = changeset |> put_change(:payload, params) |> validate_params(type, params)

    # Hashed only once the params are known flat and scalar: nothing else has
    # a canonical form.
    if changeset.valid? do
      put_change(changeset, :payload_hash, Crypto.payload_hash(params))
    else
      changeset
    end
  end

  defp validate_params(changeset, type, params) do
    Enum.reduce(Params.validate(type, params), changeset, fn {key, message}, changeset ->
      # Keyed by `payload` to stay valid Ecto; `Sca.Errors.to_map/1` promotes
      # `param` back to the key.
      add_error(changeset, :payload, message, param: key)
    end)
  end
end
