defmodule Sca.Actions.ApiToken do
  @moduledoc """
  Issuing and retiring a merchant's API keys.

  The key is returned once, in the clear, and never again — the same contract
  as a device's access token or a new member's password.
  """

  import Sca.Actions.Helpers

  require Logger

  alias Sca.Crypto
  alias Sca.Models
  alias Sca.Repos.ApiTokenRepo

  @prefix "sca"

  @doc """
  Issues a key for a merchant.

  Returns `%{api_token: record, token: "sca_…"}`; the string is the only copy.
  """
  @spec issue(Models.Tenant.t(), map()) ::
          {:ok, %{api_token: Models.ApiToken.t(), token: String.t()}}
          | {:error, Ecto.Changeset.t()}
  def issue(%Models.Tenant{} = tenant, attrs \\ %{}) do
    token = "#{@prefix}_#{Crypto.random_token(32)}"

    attrs =
      attrs
      |> stringify()
      |> Map.put("tenant_id", tenant.id)
      |> Map.put("token_hash", Crypto.token_digest(token))
      |> Map.put("preview", preview(token))

    case ApiTokenRepo.create(attrs) do
      {:ok, api_token} ->
        Logger.info("[actions.api_token.issue] #{api_token.public_id} for #{tenant.public_id}")

        {:ok, %{api_token: api_token, token: token}}

      {:error, error} ->
        Logger.warning("[actions.api_token.issue] rejected: #{reason(error)}")

        {:error, error}
    end
  end

  @doc "Retires a key. Requests presenting it stop working immediately."
  @spec revoke(Models.ApiToken.t()) ::
          {:ok, Models.ApiToken.t()} | {:error, Ecto.Changeset.t()}
  def revoke(%Models.ApiToken{} = api_token) do
    case ApiTokenRepo.revoke(api_token) do
      {:ok, api_token} ->
        Logger.info("[actions.api_token.revoke] #{api_token.public_id} revoked")

        {:ok, api_token}

      {:error, error} ->
        Logger.warning("[actions.api_token.revoke] #{api_token.public_id}: #{reason(error)}")

        {:error, error}
    end
  end

  # Enough to tell two keys apart in a list, not enough to be one.
  defp preview(token), do: String.slice(token, 0, 11) <> "…"
end
