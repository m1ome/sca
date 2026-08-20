defmodule ScaApi.MerchantController do
  @moduledoc """
  The merchant-facing API, `/api/merchant/v1`.

  Every request arrives inside a `Sca.Scope` built from the API key, so a
  handler cannot reach another merchant's data even by mistake: the lookups it
  is given are already narrowed to whoever presented the key.

  Resources are named by their UUID. Anything that creates one honours an
  `Idempotency-Key` header: a merchant whose request timed out cannot know what
  happened, so sending it again must not raise a second card.

  For an approval that key *is* `external_id` — the merchant's own reference,
  already unique per tenant — and the header only fills it in when the body did
  not. A binding needs a key of its own, because its `external_id` names a
  person, and enrolling that person again is how a lost phone gets replaced.
  """

  use ScaApi, :controller

  alias Sca.Actions
  alias Sca.Repo
  alias Sca.Repos.BindingRepo
  alias Sca.Repos.RequestRepo
  alias Sca.Scope
  alias ScaApi.JSON

  @page_size 50
  @max_page_size 100

  @doc """
  Starts an enrollment and returns the activation code.

  Re-enrolling an `external_id` replaces that person's device rather than
  adding a second — the merchant's own identifier is what a binding is for.
  """
  def create_binding(conn, params) do
    tenant = conn.assigns.current_tenant
    key = idempotency_key(conn)

    case existing(tenant, key, &BindingRepo.get_by_idempotency_key/2) do
      # Not 201, and the same activation code: a fresh one would invalidate the
      # QR the merchant may already be showing.
      {:ok, binding} -> json(conn, enrollment(conn, binding))
      :none -> enroll(conn, tenant, key, params)
    end
  end

  defp enroll(conn, tenant, key, params) do
    attrs = params |> binding_attrs() |> Map.put("idempotency_key", key)

    case Actions.Binding.enroll(tenant, attrs) do
      {:ok, binding} ->
        conn |> put_status(:created) |> json(enrollment(conn, binding))

      {:error, changeset} ->
        # Two calls with the same key at the same moment: one of them created
        # the row, and this is the other one.
        case existing(tenant, key, &BindingRepo.get_by_idempotency_key/2) do
          {:ok, binding} -> json(conn, enrollment(conn, binding))
          :none -> invalid(conn, changeset)
        end
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
    with {:ok, binding} <- fetch_binding(conn, params["binding"]) do
      raise_approval(conn, binding, params)
    end
  end

  defp raise_approval(conn, binding, params) do
    tenant = conn.assigns.current_tenant
    reference = approval_reference(conn, params)

    case existing(tenant, reference, &RequestRepo.get_by_external_id/2) do
      {:ok, request} -> json(conn, JSON.approval(request, binding))
      :none -> raise_new_approval(conn, binding, reference, params)
    end
  end

  defp raise_new_approval(conn, binding, reference, params) do
    attrs = params |> approval_attrs() |> Map.put("external_id", reference)

    case Actions.Request.create(binding, attrs) do
      {:ok, request} ->
        conn |> put_status(:created) |> json(JSON.approval(request, binding))

      {:error, :binding_not_active} ->
        error(conn, :conflict, "binding_not_active", "That device cannot answer requests.")

      {:error, %Ecto.Changeset{} = changeset} ->
        approval_refused(conn, binding, reference, changeset)
    end
  end

  defp approval_refused(conn, binding, reference, changeset) do
    case existing(conn.assigns.current_tenant, reference, &RequestRepo.get_by_external_id/2) do
      {:ok, request} -> json(conn, JSON.approval(request, binding))
      :none -> invalid(conn, changeset)
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

  # A device is named by its id, or by the merchant's own reference — which is
  # often the only identifier they kept.
  defp fetch_binding(conn, reference) when is_binary(reference) do
    scope = conn.assigns.current_scope

    case Scope.fetch_binding_by_id(scope, reference) do
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
    case Scope.fetch_request_by_id(conn.assigns.current_scope, id) do
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
      "expires_at" => params["expires_at"]
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp page(params) do
    %{"page" => params["page"] || 1, "page_size" => min(page_size(params), @max_page_size)}
  end

  # A query string carries "50", not 50, and `min/2` between a string and an
  # integer answers the integer — so a size has to be a number before it is
  # capped, or every list comes back at the maximum.
  defp page_size(params) do
    case params["page_size"] do
      size when is_integer(size) -> size
      size when is_binary(size) -> parse_page_size(size)
      _absent -> @page_size
    end
  end

  defp parse_page_size(size) do
    case Integer.parse(size) do
      {size, ""} -> size
      _other -> @page_size
    end
  end

  # The phone is told where to come back to, so a merchant keeps no address of
  # ours in their configuration. This endpoint is the one that knows it.
  defp enrollment(conn, binding) do
    JSON.enrollment(binding, conn.assigns.current_tenant, ScaApi.Endpoint.url())
  end

  # An approval is identified by the merchant's own reference; the header is
  # how someone who does not use one still gets a retry-safe call.
  defp approval_reference(conn, params) do
    case params["external_id"] do
      reference when is_binary(reference) and reference != "" -> reference
      _absent -> idempotency_key(conn)
    end
  end

  defp idempotency_key(conn) do
    case get_req_header(conn, "idempotency-key") do
      [key | _rest] -> String.trim(key)
      [] -> nil
    end
  end

  # What this key already produced for this merchant, if anything.
  defp existing(_tenant, key, _find) when key in [nil, ""], do: :none

  defp existing(tenant, key, find) do
    case find.(tenant, key) do
      {:ok, entity} -> {:ok, entity}
      {:error, :not_found} -> :none
    end
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
