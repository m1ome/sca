defmodule ScaAdmin.ApprovalsLive do
  @moduledoc """
  Every approval on the platform, whoever raised it.

  Admin rows keep the merchant in view and link to them: an internal console
  that shows a request without saying whose it is makes support guess.
  """

  use ScaAdmin, :live_view

  alias Sca.Models.Request
  alias Sca.Repo
  alias Sca.Repos.RequestRepo
  alias Sca.Repos.TenantRepo
  alias Sca.Search

  @statuses Ecto.Enum.values(Request, :status)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Approvals",
       status_options: options(@statuses),
       tenant_options: tenant_options()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {requests, meta} = RequestRepo.page(flop(params))

    {:noreply,
     socket
     |> assign(
       status: params["status"] || "",
       tenant: params["tenant"] || "",
       search: params["search"] || "",
       meta: meta
     )
     |> stream(:requests, Repo.preload(requests, [:tenant, :binding]), reset: true)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply, push_patch(socket, to: ~p"/approvals?#{query(params, 1)}")}
  end

  def handle_event("page", %{"page" => page}, socket) do
    filters = %{
      "status" => socket.assigns.status,
      "tenant" => socket.assigns.tenant,
      "search" => socket.assigns.search
    }

    {:noreply, push_patch(socket, to: ~p"/approvals?#{query(filters, page)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_admin={@current_admin} active="Approvals">
      <.page_header
        eyebrow="Platform"
        title="Approvals"
        description="Every request raised by every merchant on this cluster."
      />

      <form phx-change="filter" class="mb-4 grid gap-3 sm:grid-cols-3 lg:max-w-2xl">
        <.input
          type="select"
          name="tenant"
          value={@tenant}
          label="Merchant"
          prompt="All merchants"
          options={@tenant_options}
        />
        <.input
          type="select"
          name="status"
          value={@status}
          label="Status"
          prompt="All statuses"
          options={@status_options}
        />
        <.input
          name="search"
          value={@search}
          label="Find"
          placeholder="REQ-4711 or a uuid"
          help="An id from a log, a webhook or the API."
        />
      </form>

      <.surface>
        <.list_header title="Requests" description={"#{@meta.total_count} in total"} />

        <.table id="approvals" rows={@streams.requests} stream>
          <:col :let={request} label="ID" width="w-28" hide_below="sm">
            <span class="font-mono text-xs text-muted">{request.public_id}</span>
          </:col>
          <:col :let={request} label="Request">
            <p class="truncate font-medium">{request.title}</p>
            <p class="truncate text-xs text-muted">
              {String.capitalize(to_string(request.type))} · {request.binding.external_id}
            </p>
          </:col>
          <:col :let={request} label="Merchant" width="w-44" hide_below="sm">
            <.link
              navigate={~p"/tenants/#{request.tenant.public_id}"}
              class="truncate font-medium text-brand hover:underline"
            >
              {request.tenant.name}
            </.link>
          </:col>
          <:col :let={request} label="State" width="w-32">
            <.status value={request.status} />
          </:col>
          <:col :let={request} label="When" width="w-44" hide_below="md">
            <span class="text-muted" title={Format.datetime(moment(request))}>
              {timestamp(request)}
            </span>
          </:col>
        </.table>
      </.surface>

      <div
        :if={@meta.total_pages > 1}
        class="mt-4 flex items-center justify-between text-xs text-muted"
      >
        <span>Page {@meta.current_page} of {@meta.total_pages}</span>

        <div class="flex gap-2">
          <.button
            variant="secondary"
            phx-click="page"
            phx-value-page={@meta.previous_page}
            disabled={is_nil(@meta.previous_page)}
          >
            Previous
          </.button>
          <.button
            variant="secondary"
            phx-click="page"
            phx-value-page={@meta.next_page}
            disabled={is_nil(@meta.next_page)}
          >
            Next
          </.button>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp moment(%{decided_at: nil} = request), do: request.inserted_at
  defp moment(request), do: request.decided_at

  defp timestamp(%{decided_at: nil} = request),
    do: "Raised #{Format.relative(request.inserted_at)}"

  defp timestamp(request),
    do: "#{String.capitalize(to_string(request.status))} #{Format.relative(request.decided_at)}"

  defp flop(params) do
    filters =
      [
        filter("status", params["status"]),
        filter("tenant_id", params["tenant"]),
        Search.filter(params["search"])
      ]
      |> Enum.reject(&is_nil/1)

    %{"page" => params["page"] || 1, "page_size" => 20, "filters" => filters}
  end

  defp filter(_field, value) when value in [nil, ""], do: nil
  defp filter(field, value), do: %{"field" => field, "op" => "==", "value" => value}

  defp query(params, page) do
    %{
      "status" => params["status"],
      "tenant" => params["tenant"],
      "search" => params["search"],
      "page" => page
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
  end

  defp options(values) do
    Enum.map(values, fn value -> {value |> to_string() |> String.capitalize(), value} end)
  end

  defp tenant_options do
    Enum.map(TenantRepo.list_all(), fn tenant -> {tenant.name, tenant.id} end)
  end
end
