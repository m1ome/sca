defmodule Sca.Models.ApiToken do
  @moduledoc """
  A merchant's key to the API.

  Stored as a digest, like every other bearer in this system: the row is
  useless to whoever reads the database. What the console can still show is the
  first few characters, so a merchant can tell two keys apart without us
  keeping either.

  A tenant may hold several — that is what makes rotation possible without a
  minute of downtime: issue the new one, move traffic, revoke the old.
  """

  use Sca.Schema, public_id: "KEY"

  @required_fields ~w(token_hash preview tenant_id)a
  @optional_fields ~w(name)a
  @all_fields @required_fields ++ @optional_fields

  @type t() :: %__MODULE__{}

  @derive {Flop.Schema,
           filterable: [:public_id, :tenant_id],
           sortable: [:inserted_at],
           default_order: %{order_by: [:inserted_at], order_directions: [:desc]}}
  schema "api_tokens" do
    public_id_field()

    field :name, :string, default: ""
    field :token_hash, :string, redact: true
    field :preview, :string

    field :last_used_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    belongs_to :tenant, Sca.Models.Tenant

    timestamps()
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, @all_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, max: 80)
    |> assoc_constraint(:tenant)
    |> unique_constraint(:token_hash)
  end

  @doc "Changeset that retires a key for good."
  def revocation_changeset(token), do: change(token, revoked_at: Timex.now())

  @doc "Whether the key may still authenticate a request."
  def active?(%__MODULE__{revoked_at: nil}), do: true
  def active?(%__MODULE__{}), do: false
end
