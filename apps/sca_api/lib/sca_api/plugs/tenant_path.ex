defmodule ScaApi.TenantPath do
  @moduledoc """
  Resolves the merchant named in the path, for device calls made under
  `/t/:tenant` — by uuid or by the readable `TNT-…`.

  The QR hands the phone a tenant-scoped base URL and every later call keeps
  that prefix, so the merchant is visible in the path — to a proxy deciding
  rate limits, to a log, and here: an enrollment token or a session belonging
  to another merchant is refused rather than quietly served.

  Without the prefix the plug does nothing; the token alone still resolves the
  binding, which is how a device bound before the prefix existed keeps working.
  """

  import Plug.Conn

  alias Sca.Repos.TenantRepo

  def init(opts), do: opts

  def call(%{params: %{"tenant" => reference}} = conn, _opts) do
    case fetch(reference) do
      {:ok, tenant} -> assign(conn, :path_tenant, tenant)
      {:error, :not_found} -> halt_with(conn, 404, "unknown_merchant")
    end
  end

  def call(conn, _opts), do: conn

  # The prefix is an address rather than a resource id: it goes into a QR and
  # gets typed in by hand when the camera will not cooperate, so `TNT-1` is
  # worth accepting next to the uuid.
  defp fetch(reference) do
    case Ecto.UUID.cast(reference) do
      {:ok, uuid} -> TenantRepo.get(uuid)
      :error -> TenantRepo.get_by_public_id(reference)
    end
  end

  @doc """
  Refuses an entity that belongs to a different merchant than the path names.

  Returns the conn, halted when they disagree.
  """
  @spec ensure_owner(Plug.Conn.t(), %{:tenant_id => String.t(), optional(atom()) => any()} | nil) ::
          Plug.Conn.t()
  def ensure_owner(%{assigns: %{path_tenant: tenant}} = conn, %{tenant_id: tenant_id}) do
    if tenant.id == tenant_id, do: conn, else: halt_with(conn, 404, "unknown_merchant")
  end

  def ensure_owner(conn, _entity), do: conn

  defp halt_with(conn, status, code) do
    body = %{error: %{code: code, message: "This merchant does not exist here."}}

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end
end
