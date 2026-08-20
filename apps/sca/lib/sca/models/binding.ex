defmodule Sca.Models.Binding do
  @moduledoc """
  A device bound to a tenant.

  `external_id` is the merchant's own identifier for its owner, unique per
  tenant: enrolling the same person again replaces their binding instead of
  leaving a dead one behind.
  """

  use Sca.Schema, public_id: "BIN"

  @statuses ~w(pending active revoked)a
  @push_platforms ~w(ios android)a
  @default_algorithm "ecdsa-p256"

  @enroll_ttl Timex.Duration.from_minutes(15)
  # Sliding window: a device that opens the app at least this often never has to
  # scan a QR again, and a stolen token dies on its own after it.
  @access_token_ttl Timex.Duration.from_days(30)
  # How long past expiry a token may still reach the refresh path, and only it.
  # Renewing costs a hardware-key signature anyway, so a stolen bearer gains
  # nothing; a user who ignored the app for a month is spared a re-scan.
  @renewal_grace Timex.Duration.from_days(30)
  # PSD2 RTS Art 4(3)(b): lock the credential after five consecutive failures.
  @max_failed_attempts 5

  @required_fields ~w(external_id status tenant_id)a
  @optional_fields ~w(name push_token push_platform idempotency_key)a
  @all_fields @required_fields ++ @optional_fields

  @activation_fields ~w(public_key algorithm device_info attested attestation_type
                        attestation_level push_token push_platform name)a
  @enrollment_fields ~w(enroll_token enroll_nonce enroll_expires_at)a

  @type t() :: %__MODULE__{}

  @derive {Flop.Schema,
           filterable: [:id, :public_id, :external_id, :status, :tenant_id],
           sortable: [:inserted_at, :last_seen_at],
           default_order: %{order_by: [:inserted_at], order_directions: [:desc]}}
  schema "bindings" do
    public_id_field()

    field :external_id, :string
    field :name, :string, default: ""

    # The merchant's own key for "this call, not another one". Unique per
    # tenant, so a retried enrollment finds its own row instead of resetting it.
    field :idempotency_key, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending

    field :enroll_token, :string
    field :enroll_nonce, :string
    field :enroll_expires_at, :utc_datetime_usec

    field :access_token_hash, :string, redact: true
    field :access_token_expires_at, :utc_datetime_usec
    field :refresh_nonce, :string, redact: true

    field :public_key, :string
    field :algorithm, :string, default: @default_algorithm
    field :device_info, :map, default: %{}
    field :attested, :boolean, default: false
    field :attestation_type, :string
    field :attestation_level, :string

    field :push_token, :string
    field :push_platform, Ecto.Enum, values: @push_platforms

    field :failed_attempts, :integer, default: 0

    field :activated_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec

    belongs_to :tenant, Sca.Models.Tenant
    has_many :requests, Sca.Models.Request

    timestamps()
  end

  @doc "How long an enrollment QR stays scannable."
  def enroll_ttl, do: @enroll_ttl

  @doc "Lifetime of a device access token."
  def access_token_ttl, do: @access_token_ttl

  @doc "How long an expired token may still be refreshed."
  def renewal_grace, do: @renewal_grace

  @doc "A duration in whole seconds."
  def seconds(%Timex.Duration{} = duration) do
    duration |> Timex.Duration.to_seconds() |> trunc()
  end

  @doc "Consecutive signature failures before the binding is revoked."
  def max_failed_attempts, do: @max_failed_attempts

  def changeset(binding, attrs) do
    binding
    |> cast(attrs, @all_fields)
    |> validate_required(@required_fields)
    |> validate_length(:external_id, min: 1, max: 160)
    |> assoc_constraint(:tenant)
    |> unique_constraint(:external_id, name: :bindings_tenant_id_external_id_index)
    |> unique_constraint(:idempotency_key, name: :bindings_tenant_id_idempotency_key_index)
  end

  @doc """
  Changeset for a fresh, not yet scanned enrollment.

  Also used to re-enroll an existing `external_id`, so everything the previous
  device left behind is wiped here: a binding waiting for a scan must not carry
  a usable key or push token from the phone it is replacing.
  """
  def enrollment_changeset(binding, attrs) do
    binding
    |> changeset(attrs)
    |> cast(attrs, @enrollment_fields)
    |> reset_device()
    |> put_change(:status, :pending)
    |> validate_required([:enroll_token, :enroll_expires_at])
    |> unique_constraint(:enroll_token)
  end

  @doc """
  Changeset applied when the device finishes enrollment: it hands over its
  public key, and the enrollment token is burned.
  """
  def activation_changeset(binding, attrs) do
    binding
    |> cast(attrs, @activation_fields)
    |> validate_required([:public_key, :algorithm])
    |> put_change(:status, :active)
    |> put_change(:activated_at, Timex.now())
    |> put_change(:enroll_token, nil)
    |> put_change(:enroll_nonce, nil)
    |> put_change(:enroll_expires_at, nil)
    |> put_change(:failed_attempts, 0)
    |> validate_public_key()
  end

  defp validate_public_key(changeset) do
    algorithm = get_field(changeset, :algorithm)

    validate_change(changeset, :public_key, fn :public_key, public_key ->
      case Sca.Crypto.validate_public_key(algorithm, public_key) do
        :ok -> []
        {:error, reason} -> [public_key: "is not a valid key (#{inspect(reason)})"]
      end
    end)
  end

  defp reset_device(changeset) do
    changeset
    |> clear_session()
    |> put_change(:public_key, nil)
    |> put_change(:algorithm, @default_algorithm)
    |> put_change(:device_info, %{})
    |> put_change(:attested, false)
    |> put_change(:attestation_type, nil)
    |> put_change(:attestation_level, nil)
    |> put_change(:push_token, nil)
    |> put_change(:push_platform, nil)
    |> put_change(:failed_attempts, 0)
    |> put_change(:activated_at, nil)
    |> put_change(:revoked_at, nil)
  end

  @doc """
  Changeset that takes the device out of service for good.

  The session dies with it: a revoked binding must not be reachable with a
  token that still had time left on it.
  """
  def revocation_changeset(binding) do
    binding
    |> change(status: :revoked, revoked_at: Timex.now())
    |> put_change(:push_token, nil)
    |> clear_session()
  end

  defp clear_session(changeset) do
    changeset
    |> put_change(:access_token_hash, nil)
    |> put_change(:access_token_expires_at, nil)
    |> put_change(:refresh_nonce, nil)
  end
end
