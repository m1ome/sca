defmodule Sca.Models.Tenant do
  @moduledoc """
  A merchant's container: everything else in the system hangs off a tenant.
  """

  use Sca.Schema, public_id: "TNT"

  alias Sca.Models.Embed.TenantSettings

  @statuses ~w(active suspended)a

  @required_fields ~w(name)a
  @optional_fields ~w(status)a
  @all_fields @required_fields ++ @optional_fields

  @type t() :: %__MODULE__{}

  @derive {Flop.Schema,
           filterable: [:public_id, :name, :status],
           sortable: [:inserted_at, :name],
           default_order: %{order_by: [:inserted_at], order_directions: [:desc]}}

  schema "tenants" do
    public_id_field()

    field :name, :string
    field :status, Ecto.Enum, values: @statuses, default: :active

    embeds_one :settings, TenantSettings, on_replace: :update, defaults_to_struct: true

    has_many :users, Sca.Models.User
    has_many :bindings, Sca.Models.Binding
    has_many :requests, Sca.Models.Request

    timestamps()
  end

  def changeset(tenant, attrs) do
    tenant
    |> cast(attrs, @all_fields)
    |> cast_embed(:settings)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 160)
  end
end
