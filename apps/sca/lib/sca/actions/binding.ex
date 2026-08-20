defmodule Sca.Actions.Binding do
  @moduledoc """
  The life of a bound device: enrollment, binding, its session, and how it ends.

  Resolving a bearer token to a binding is not here: that is endpoint plumbing.
  """

  import Sca.Actions.Helpers

  require Logger

  alias Sca.Crypto
  alias Sca.Models
  alias Sca.Repo
  alias Sca.Repos.BindingRepo
  alias Sca.Telemetry
  alias Sca.Webhooks

  @type session() :: %{
          binding: Models.Binding.t(),
          access_token: String.t(),
          expires_at: DateTime.t()
        }

  @doc """
  Starts an enrollment: a pending binding plus the token and challenge for the
  QR code.

  Re-enrolling an `external_id` reuses its row — no pile of dead bindings for
  one person — and clears what the previous device left: key, session, token.
  """
  @spec enroll(Models.Tenant.t(), map()) ::
          {:ok, Models.Binding.t()} | {:error, Ecto.Changeset.t()}
  def enroll(%Models.Tenant{} = tenant, attrs \\ %{}) do
    attrs = enrollment_attrs(tenant, attrs)

    case BindingRepo.enroll(existing(tenant, attrs["external_id"]), attrs) do
      {:ok, binding} ->
        Logger.info("[actions.binding.enroll] #{binding.public_id} for #{tenant.public_id}")

        {:ok, binding}

      {:error, error} ->
        Logger.warning(
          "[actions.binding.enroll] rejected for #{tenant.public_id}: #{reason(error)}"
        )

        {:error, error}
    end
  end

  @doc """
  Completes an enrollment: the device presents its public key, gets a session.

  The row is locked, so a QR scanned twice at once still binds one device. The
  raw access token is returned once; only its digest is stored.
  """
  @spec bind(String.t(), map()) ::
          {:ok, session()}
          | {:error, :not_found | :enrollment_used | :enrollment_expired | Ecto.Changeset.t()}
  def bind(enroll_token, attrs) when is_binary(enroll_token) do
    access_token = Crypto.random_token(32)
    expires_at = Timex.shift(Timex.now(), duration: Models.Binding.access_token_ttl())

    Repo.transact(fn ->
      with {:ok, pending} <- BindingRepo.lock_by_enroll_token(enroll_token),
           :ok <- ensure_enrollable(pending),
           {:ok, binding} <- activate(pending, attrs, access_token, expires_at),
           {:ok, _delivery} <- Webhooks.queue("binding.activated", binding) do
        Logger.info(
          "[actions.binding.bind] #{binding.public_id} activated, attested=#{binding.attested}"
        )

        Telemetry.emit([:binding, :bound], %{count: 1}, %{tenant_id: binding.tenant_id})

        {:ok, %{binding: binding, access_token: access_token, expires_at: expires_at}}
      else
        {:error, error} ->
          Logger.warning("[actions.binding.bind] refused: #{reason(error)}")

          {:error, error}
      end
    end)
  end

  @doc """
  Issues the one-shot challenge a device signs with its hardware key before
  refreshing its token.
  """
  @spec issue_refresh_challenge(Models.Binding.t()) ::
          {:ok, %{binding: Models.Binding.t(), nonce: String.t()}}
          | {:error, :revoked | Ecto.Changeset.t()}
  def issue_refresh_challenge(%Models.Binding{status: :active} = binding) do
    case BindingRepo.change(binding, refresh_nonce: Crypto.random_token(16)) do
      {:ok, binding} ->
        {:ok, %{binding: binding, nonce: binding.refresh_nonce}}

      {:error, error} ->
        Logger.warning(
          "[actions.binding.issue_refresh_challenge] #{binding.public_id}: #{reason(error)}"
        )

        {:error, error}
    end
  end

  def issue_refresh_challenge(%Models.Binding{} = binding) do
    Logger.warning("[actions.binding.issue_refresh_challenge] #{binding.public_id} is revoked")

    {:error, :revoked}
  end

  @doc """
  Extends the session against a proof-of-possession signature over the
  outstanding challenge.

  The bearer names the binding, the hardware-key signature authorises, so a
  stolen token cannot renew itself. The challenge is single-use; the token is
  not rotated, because a partial failure would lock the device out.
  """
  @spec refresh_session(Models.Binding.t(), String.t()) ::
          {:ok, Models.Binding.t()} | {:error, :revoked | :no_challenge | :invalid_proof}
  def refresh_session(%Models.Binding{status: :active} = binding, signature) do
    with {:ok, nonce} <- outstanding_challenge(binding),
         :ok <- verify_possession(binding, nonce, signature),
         {:ok, binding} <- extend_session(binding) do
      Logger.info("[actions.binding.refresh_session] #{binding.public_id} extended")

      {:ok, binding}
    else
      {:error, error} ->
        Logger.warning(
          "[actions.binding.refresh_session] #{binding.public_id} refused: #{reason(error)}"
        )

        {:error, error}
    end
  end

  def refresh_session(%Models.Binding{} = binding, _signature) do
    Logger.warning("[actions.binding.refresh_session] #{binding.public_id} is revoked")

    {:error, :revoked}
  end

  @doc """
  Records a push token the OS rotated (reinstall, restore, update), so
  notifications keep landing without a re-bind.
  """
  @spec update_push_token(Models.Binding.t(), String.t(), atom()) ::
          {:ok, Models.Binding.t()} | {:error, :revoked | Ecto.Changeset.t()}
  def update_push_token(%Models.Binding{status: :active} = binding, token, platform) do
    case BindingRepo.update(binding, %{push_token: token, push_platform: platform}) do
      {:ok, binding} ->
        Logger.info("[actions.binding.update_push_token] #{binding.public_id} on #{platform}")

        {:ok, binding}

      {:error, error} ->
        Logger.warning(
          "[actions.binding.update_push_token] #{binding.public_id}: #{reason(error)}"
        )

        {:error, error}
    end
  end

  def update_push_token(%Models.Binding{} = binding, _token, _platform) do
    Logger.warning("[actions.binding.update_push_token] #{binding.public_id} is revoked")

    {:error, :revoked}
  end

  @doc """
  Takes the device out of service for good.

  The session dies with it: a revoked binding must not stay reachable with a
  token that had time left. The merchant is told — a device that stops approving
  payments is theirs to explain.
  """
  @spec revoke(Models.Binding.t(), atom()) :: {:ok, Models.Binding.t()} | {:error, term()}
  def revoke(%Models.Binding{} = binding, cause \\ :requested) do
    Repo.transact(fn ->
      with {:ok, binding} <- BindingRepo.revoke(binding),
           {:ok, _delivery} <- Webhooks.queue("binding.revoked", binding) do
        Logger.info("[actions.binding.revoke] #{binding.public_id} revoked (#{cause})")

        Telemetry.emit([:binding, :revoked], %{count: 1}, %{
          reason: cause,
          tenant_id: binding.tenant_id
        })

        {:ok, binding}
      else
        {:error, error} ->
          Logger.warning("[actions.binding.revoke] #{binding.public_id} failed: #{reason(error)}")

          {:error, error}
      end
    end)
  end

  defp enrollment_attrs(tenant, attrs) do
    attrs
    |> stringify()
    |> Map.put("tenant_id", tenant.id)
    |> Map.put_new_lazy("enroll_token", fn -> Crypto.random_token(24) end)
    |> Map.put_new_lazy("enroll_nonce", fn -> Crypto.random_token(24) end)
    |> Map.put_new_lazy("enroll_expires_at", fn ->
      Timex.shift(Timex.now(), duration: Models.Binding.enroll_ttl())
    end)
  end

  defp existing(tenant, external_id) when is_binary(external_id) do
    case BindingRepo.get_by_external_id(tenant, external_id) do
      {:ok, binding} -> binding
      {:error, :not_found} -> %Models.Binding{}
    end
  end

  defp existing(_tenant, _external_id), do: %Models.Binding{}

  defp ensure_enrollable(%Models.Binding{status: status}) when status != :pending,
    do: {:error, :enrollment_used}

  defp ensure_enrollable(%Models.Binding{enroll_expires_at: nil}),
    do: {:error, :enrollment_expired}

  defp ensure_enrollable(%Models.Binding{enroll_expires_at: deadline}) do
    if Timex.before?(deadline, Timex.now()), do: {:error, :enrollment_expired}, else: :ok
  end

  defp activate(binding, attrs, access_token, expires_at) do
    binding
    |> Models.Binding.activation_changeset(stringify(attrs))
    |> Ecto.Changeset.put_change(:access_token_hash, Crypto.token_digest(access_token))
    |> Ecto.Changeset.put_change(:access_token_expires_at, expires_at)
    |> Repo.update()
  end

  defp outstanding_challenge(%Models.Binding{refresh_nonce: nonce})
       when is_binary(nonce) and nonce != "",
       do: {:ok, nonce}

  defp outstanding_challenge(%Models.Binding{}), do: {:error, :no_challenge}

  defp verify_possession(binding, nonce, signature) do
    message = Crypto.refresh_signing_string(binding.id, nonce)

    case Crypto.verify(binding.algorithm, binding.public_key, message, signature) do
      :ok -> :ok
      {:error, _reason} -> {:error, :invalid_proof}
    end
  end

  defp extend_session(binding) do
    BindingRepo.change(binding,
      access_token_expires_at:
        Timex.shift(Timex.now(), duration: Models.Binding.access_token_ttl()),
      refresh_nonce: nil
    )
  end
end
