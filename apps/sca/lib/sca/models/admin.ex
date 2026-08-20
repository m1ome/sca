defmodule Sca.Models.Admin do
  @moduledoc """
  Someone on our side of the fence, with access to the internal admin panel.

  They sign in with an email and a password, like a merchant's team member —
  the console is internal, so there is no SSO and no tenant to name.
  """

  use Sca.Schema, public_id: "ADM"

  @roles ~w(superadmin support)a
  @statuses ~w(active disabled)a
  @min_password_length 12

  @required_fields ~w(email role status)a
  @optional_fields ~w(name last_login_at)a
  @all_fields @required_fields ++ @optional_fields

  @type t() :: %__MODULE__{}

  @derive {Flop.Schema,
           filterable: [:public_id, :email, :role, :status],
           sortable: [:inserted_at, :email],
           default_order: %{order_by: [:inserted_at], order_directions: [:desc]}}

  schema "admins" do
    public_id_field()

    field :password_hash, :string, redact: true
    field :password, :string, virtual: true, redact: true

    field :email, :string
    field :name, :string, default: ""
    field :role, Ecto.Enum, values: @roles, default: :support
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :last_login_at, :utc_datetime_usec

    timestamps()
  end

  @doc "Changeset for creating an admin together with their password."
  def registration_changeset(admin, attrs) do
    admin
    |> changeset(attrs)
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> put_password_hash()
  end

  @doc "Changeset for replacing an admin's password."
  def password_changeset(admin, attrs) do
    admin
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> put_password_hash()
  end

  def changeset(admin, attrs) do
    admin
    |> cast(attrs, @all_fields)
    |> validate_required(@required_fields)
    |> update_change(:email, fn email -> email |> String.trim() |> String.downcase() end)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, message: "must be an email")
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email)
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
