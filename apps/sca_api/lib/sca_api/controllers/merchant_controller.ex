defmodule ScaApi.MerchantController do
  @moduledoc """
  The merchant-facing API, `/api/merchant/v1`.

  Every request arrives inside a `Sca.Scope` built from the API key, so a
  handler cannot reach another merchant's data even by mistake: the lookups it
  is given are already narrowed to whoever presented the key.
  """

  use ScaApi, :controller

  alias Sca.Actions
  alias Sca.Repo
  alias Sca.Repos.BindingRepo
  alias Sca.Repos.RequestRepo
  alias Sca.Scope
  alias ScaApi.JSON

  @page_size 50

  @doc """
  Starts an enrollment and returns the activation code.

  Re-enrolling an `external_id` replaces that person's device rather than
  adding a second — the merchant's own identifier is what a binding is for.
  """
  def create_binding(conn, params) do
    case Actions.Binding.enroll(conn.assigns.current_tenant, binding_attrs(params)) do
      {:ok, binding} -> conn |> put_status(:created) |> json(JSON.enrollment(binding))
      {:error, changeset} -> invalid(conn, changeset)
    end
  end

  def list_bindings(conn, params) do
    {bindings, meta} = BindingRepo.page_for_tenant(conn.assigns.current_tenant, page(params))

    json(conn, JSON.page(Enum.map(bindings, &JSON.binding/1), meta))
  end

  def show_binding(conn, %{"id" => id}) do
    with {:ok, binding} <- fetch_binding(conn, id) do
      json(conn, JSON.binding(binding))
    end
  end

  def revoke_binding(conn, %{"id" => id}) do
    with {:ok, binding} <- fetch_binding(conn, id),
         {:ok, revoked} <- Actions.Binding.revoke(binding, :merchant) do
      json(conn, JSON.binding(revoked))
    end
  end

  @doc """
  Raises an approval on a device.

  The device is named by the merchant's own reference, which is the only
  identifier they have to keep: `binding` accepts either that or `BIN-…`.
  """
  def create_approval(conn, params) do
    with {:ok, binding} <- fetch_binding(conn, params["binding"]),
         {:ok, request} <- Actions.Request.create(binding, approval_attrs(params)) do
      conn |> put_status(:created) |> json(JSON.approval(request, binding))
    else
      {:error, :binding_not_active} ->
        error(conn, :conflict, "binding_not_active", "That device cannot answer requests.")

      {:error, %Ecto.Changeset{} = changeset} ->
        invalid(conn, changeset)

      other ->
        other
    end
  end

  def list_approvals(conn, params) do
    {requests, meta} = RequestRepo.page_for_tenant(conn.assigns.current_tenant, page(params))
    requests = Repo.preload(requests, :binding)

    json(conn, JSON.page(Enum.map(requests, &JSON.approval(&1, &1.binding)), meta))
  end

  def show_approval(conn, %{"id" => id}) do
    with {:ok, request} <- fetch_approval(conn, id) do
      json(conn, JSON.approval(request, Repo.preload(request, :binding).binding))
    end
  end

  @doc "Takes back a request nobody has answered yet."
  def cancel_approval(conn, %{"id" => id}) do
    with {:ok, request} <- fetch_approval(conn, id),
         {:ok, cancelled} <- Actions.Request.cancel(request) do
      json(conn, JSON.approval(cancelled, Repo.preload(cancelled, :binding).binding))
    else
      {:error, :not_pending} ->
        error(conn, :conflict, "not_pending", "This approval was already answered.")

      other ->
        other
    end
  end

  defp fetch_binding(conn, reference) when is_binary(reference) do
    scope = conn.assigns.current_scope

    case Scope.fetch_binding(scope, reference) do
      {:ok, binding} -> {:ok, binding}
      {:error, :not_found} -> by_external_id(conn, scope, reference)
    end
  end

  defp fetch_binding(conn, _missing) do
    error(conn, :bad_request, "invalid_request", "A binding reference is required.")
  end

  defp by_external_id(conn, scope, reference) do
    case Scope.fetch_binding_by_external_id(scope, reference) do
      {:ok, binding} -> {:ok, binding}
      {:error, :not_found} -> error(conn, :not_found, "not_found", "No such binding.")
    end
  end

  defp fetch_approval(conn, id) do
    case Scope.fetch_request(conn.assigns.current_scope, id) do
      {:ok, request} -> {:ok, request}
      {:error, :not_found} -> error(conn, :not_found, "not_found", "No such approval.")
    end
  end

  defp binding_attrs(params) do
    %{"external_id" => params["external_id"], "name" => params["name"] || ""}
  end

  defp approval_attrs(params) do
    %{
      "type" => params["type"],
      "title" => params["title"],
      "description" => params["description"] || "",
      "payload" => params["params"] || %{},
      "external_id" => params["external_id"],
      "expires_at" => params["expires_at"]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp page(params) do
    %{"page" => params["page"] || 1, "page_size" => min(params["page_size"] || @page_size, 100)}
  end

  defp invalid(conn, changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(
      JSON.error("invalid_request", "Some fields were rejected.", Sca.Errors.to_map(changeset))
    )
  end

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(JSON.error(code, message))
  end
end
