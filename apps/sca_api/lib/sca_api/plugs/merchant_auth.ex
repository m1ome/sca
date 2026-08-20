defmodule ScaApi.MerchantAuth do
  @moduledoc """
  Resolves a merchant's API key to the tenant it belongs to.

  The key arrives as a bearer token, is matched by digest, and the request
  continues inside a `Sca.Scope` — so a handler that forgets to check whose
  data it is touching cannot reach anyone else's.
  """

  import Plug.Conn

  alias Sca.Models.ApiToken
  alias Sca.Repos.ApiTokenRepo
  alias Sca.Repos.TenantRepo
  alias Sca.Scope

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, presented} <- bearer(conn),
         {:ok, api_token} <- ApiTokenRepo.get_by_token(presented),
         true <- ApiToken.active?(api_token),
         {:ok, tenant} <- TenantRepo.get(api_token.tenant_id),
         :active <- tenant.status do
      {:ok, _token} = ApiTokenRepo.touch(api_token)

      conn
      |> assign(:current_tenant, tenant)
      |> assign(:current_scope, Scope.for_tenant(tenant))
      |> assign(:api_token, api_token)
    else
      # "Wrong key" and "revoked key" are not facts a caller has earned.
      :suspended ->
        halt_with(conn, 403, "merchant_suspended", "This merchant is not being served.")

      _unauthorised ->
        halt_with(conn, 401, "unauthorized", "Present a valid API key.")
    end
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _rest] -> {:ok, String.trim(token)}
      ["bearer " <> token | _rest] -> {:ok, String.trim(token)}
      _missing -> :error
    end
  end

  defp halt_with(conn, status, code, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: %{code: code, message: message}}))
    |> halt()
  end
end
