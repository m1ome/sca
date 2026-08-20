defmodule Sca.Models.User do
  @moduledoc """
  A member of the merchant's team — whoever signs into the merchant cabinet.

  Not an end customer: the people who approve requests on their phones are
  never stored here, we only know their devices (`Sca.Models.Binding`).
  """

  use Sca.Schema, public_id: "USR"

  @roles ~w(owner admin viewer)a
  @statuses ~w(active disabled)a
  @min_password_length 12

  @required_fields ~w(email role status tenant_id)a
  @optional_fields ~w(name)a
  @all_fields @required_fields ++ @optional_fields

  @type t() :: %__MODULE__{}

  @derive {Flop.Schema,
           filterable: [:public_id, :email, :role, :status, :tenant_id],
           sortable: [:inserted_at, :email],
           default_order: %{order_by: [:inserted_at], order_directions: [:desc]}}

  schema "users" do
    public_id_field()

    field :email, :string
    field :name, :string, default: ""
    field :role, Ecto.Enum, values: @roles, default: :viewer
    field :status, Ecto.Enum, values: @statuses, default: :active

    field :password_hash, :string, redact: true
    field :password, :string, virtual: true, redact: true

    belongs_to :tenant, Sca.Models.Tenant

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, @all_fields)
    |> validate_required(@required_fields)
    |> validate_email()
    |> assoc_constraint(:tenant)
    |> unique_constraint(:email, name: :users_tenant_id_email_index)
  end

  @doc "Changeset for creating a user together with their password."
  def registration_changeset(user, attrs) do
    user
    |> changeset(attrs)
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> put_password_hash()
  end

  @doc "Changeset for replacing the password of an existing user."
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> put_password_hash()
  end

  defp validate_email(changeset) do
    changeset
    |> update_change(:email, fn email -> email |> String.trim() |> String.downcase() end)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "must be an email")
    |> validate_length(:email, max: 160)
  end

  defp put_password_hash(changeset) do
    changeset
    |> validate_length(:password, min: @min_password_length, max: 72)
    |> case do
      %{valid?: true, changes: %{password: password}} = changeset ->
        changeset
        |> put_change(:password_hash, Bcrypt.hash_pwd_salt(password))
        |> delete_change(:password)

      changeset ->
        changeset
    end
  end
end
