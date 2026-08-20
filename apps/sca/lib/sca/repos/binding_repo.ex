defmodule Sca.Repos.BindingRepo do
  @moduledoc """
  Persistence for bound devices. The lifecycle lives in `Sca.Actions.*`.
  """

  use Sca.Repo.Base, model: Sca.Models.Binding

  alias Sca.Crypto
  alias Sca.Models.Binding
  alias Sca.Models.Tenant

  @spec enroll(Binding.t(), map()) :: {:ok, Binding.t()} | {:error, Ecto.Changeset.t()}
  def enroll(%Binding{} = binding, attrs) do
    binding
    |> Binding.enrollment_changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc "Retires the device: status, timestamps, and the session it carried."
  @spec revoke(Binding.t()) :: {:ok, Binding.t()} | {:error, Ecto.Changeset.t()}
  def revoke(%Binding{} = binding) do
    binding
    |> Binding.revocation_changeset()
    |> Repo.update()
  end

  @doc "Records that the device checked in."
  @spec touch_last_seen(Binding.t()) :: {:ok, Binding.t()} | {:error, Ecto.Changeset.t()}
  def touch_last_seen(%Binding{} = binding), do: change(binding, last_seen_at: Timex.now())

  @doc "Finds the device bound for the merchant's own identifier."
  @spec get_by_external_id(Tenant.t(), String.t()) :: {:ok, Binding.t()} | {:error, :not_found}
  def get_by_external_id(%Tenant{id: tenant_id}, external_id) when is_binary(external_id) do
    get_by(tenant_id: tenant_id, external_id: external_id)
  end

  @doc "The binding a merchant's idempotency key already produced, if any."
  @spec get_by_idempotency_key(Tenant.t(), String.t()) ::
          {:ok, Binding.t()} | {:error, :not_found}
  def get_by_idempotency_key(%Tenant{id: tenant_id}, key) when is_binary(key) do
    get_by(tenant_id: tenant_id, idempotency_key: key)
  end

  @spec get_by_enroll_token(String.t()) :: {:ok, Binding.t()} | {:error, :not_found}
  def get_by_enroll_token(token) when is_binary(token), do: get_by(enroll_token: token)

  @doc """
  Finds the binding a device bearer token belongs to.

  Tokens are stored as digests, so the lookup hashes first — the raw token
  exists only in the response that created it.
  """
  @spec get_by_access_token(String.t()) :: {:ok, Binding.t()} | {:error, :not_found}
  def get_by_access_token(token) when is_binary(token) do
    get_by(access_token_hash: Crypto.token_digest(token))
  end

  @doc "Locks the enrollment row for the length of the surrounding transaction."
  @spec lock_by_enroll_token(String.t()) :: {:ok, Binding.t()} | {:error, :not_found}
  def lock_by_enroll_token(token) when is_binary(token), do: lock_by(enroll_token: token)

  @doc "A page of the tenant's devices, filtered and sorted by the console."
  @spec page_for_tenant(Tenant.t(), map()) :: {[Binding.t()], Flop.Meta.t()}
  def page_for_tenant(%Tenant{id: tenant_id}, params) do
    list(params, where(Binding, tenant_id: ^tenant_id))
  end

  @doc "A page of every merchant's devices, for the admin console."
  @spec page(map()) :: {[Binding.t()], Flop.Meta.t()}
  def page(params), do: list(params)

  @spec list_by_tenant(Tenant.t()) :: [Binding.t()]
  def list_by_tenant(%Tenant{id: tenant_id}), do: list_by(tenant_id: tenant_id)

  @spec list_active(Tenant.t()) :: [Binding.t()]
  def list_active(%Tenant{id: tenant_id}), do: list_by(tenant_id: tenant_id, status: :active)
end
