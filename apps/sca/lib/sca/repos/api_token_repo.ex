defmodule Sca.Repos.ApiTokenRepo do
  @moduledoc """
  Persistence for merchant API keys.
  """

  use Sca.Repo.Base, model: Sca.Models.ApiToken

  alias Sca.Crypto
  alias Sca.Models.ApiToken
  alias Sca.Models.Tenant

  @doc """
  Finds the key a request presented.

  Hashes first: the raw key exists only in the response that issued it.
  """
  @spec get_by_token(String.t()) :: {:ok, ApiToken.t()} | {:error, :not_found}
  def get_by_token(token) when is_binary(token) do
    get_by(token_hash: Crypto.token_digest(token))
  end

  @doc "Retires a key."
  @spec revoke(ApiToken.t()) :: {:ok, ApiToken.t()} | {:error, Ecto.Changeset.t()}
  def revoke(%ApiToken{} = token) do
    token
    |> ApiToken.revocation_changeset()
    |> Repo.update()
  end

  @doc "Records that the key was just used, at most once a minute."
  @spec touch(ApiToken.t()) :: {:ok, ApiToken.t()} | {:error, Ecto.Changeset.t()}
  def touch(%ApiToken{} = token) do
    if stale?(token.last_used_at) do
      change(token, last_used_at: Timex.now())
    else
      {:ok, token}
    end
  end

  @spec list_by_tenant(Tenant.t()) :: [ApiToken.t()]
  def list_by_tenant(%Tenant{id: tenant_id}) do
    list_by([tenant_id: tenant_id], order_by: [desc: :inserted_at])
  end

  # Every call would otherwise write to the same row, which is a lock the API
  # does not need to hold for a timestamp nobody reads to the second.
  defp stale?(nil), do: true
  defp stale?(last_used_at), do: Timex.diff(Timex.now(), last_used_at, :second) > 60
end
