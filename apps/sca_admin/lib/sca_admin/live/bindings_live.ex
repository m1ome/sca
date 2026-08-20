defmodule ScaAdmin.BindingsLive do
  @moduledoc """
  Every linked device on the platform, with the merchant it belongs to.
  """

  use ScaAdmin, :live_view

  alias Sca.Models.Binding
  alias Sca.Repo
  alias Sca.Repos.BindingRepo
  alias Sca.Repos.TenantRepo
  alias Sca.Search

  @statuses Ecto.Enum.values(Binding, :status)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Bindings",
       status_options: options(@statuses),
       tenant_options: tenant_options()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {bindings, meta} = BindingRepo.page(flop(params))

    {:noreply,
     socket
     |> assign(
       status: params["status"] || "",
       tenant: params["tenant"] || "",
       search: params["search"] || "",
       meta: meta
     )
     |> stream(:bindings, Repo.preload(bindings, :tenant), reset: true)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply, push_patch(socket, to: ~p"/bindings?#{query(params, 1)}")}
  end

  def handle_event("page", %{"page" => page}, socket) do
    filters = %{
      "status" => socket.assigns.status,
      "tenant" => socket.assigns.tenant,
      "search" => socket.assigns.search
    }

    {:noreply, push_patch(socket, to: ~p"/bindings?#{query(filters, page)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_admin={@current_admin} active="Bindings">
      <.page_header
        eyebrow="Platform"
        title="Bindings"
        description="The phones that can confirm approvals, whoever they belong to."
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
          label="State"
          prompt="All states"
          options={@status_options}
        />
        <.input
          name="search"
          value={@search}
          label="Find"
          placeholder="BIN-42 or a uuid"
          help="An id from a log, a webhook or the API."
        />
      </form>

      <.surface>
        <.list_header title="Devices" description={"#{@meta.total_count} in total"} />

        <.table id="bindings" rows={@streams.bindings} stream>
          <:col :let={binding} label="Device">
            <p class="truncate font-medium">{name(binding)}</p>
            <p class="truncate text-xs text-muted">{binding.external_id}</p>
          </:col>
          <:col :let={binding} label="Merchant" width="w-44" hide_below="sm">
            <.link
              navigate={~p"/tenants/#{binding.tenant.public_id}"}
              class="truncate font-medium text-brand hover:underline"
            >
              {binding.tenant.name}
            </.link>
          </:col>
          <:col :let={binding} label="Platform" width="w-24" hide_below="md">
            <span class="text-muted">{platform(binding)}</span>
          </:col>
          <:col :let={binding} label="State" width="w-32">
            <.status value={binding.status} />
          </:col>
          <:col :let={binding} label="Activity" width="w-44" hide_below="md">
            <span class="text-muted" title={Format.datetime(activity_at(binding))}>
              {timestamp(binding)}
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

  defp name(binding) do
    case String.trim(to_string(binding.name)) do
      "" -> "Unnamed device"
      name -> name
    end
  end

  defp platform(%{push_platform: nil}), do: "—"
  defp platform(%{push_platform: platform}), do: platform |> to_string() |> String.upcase()

  defp activity_at(%{status: :revoked} = binding), do: binding.revoked_at
  defp activity_at(%{status: :active} = binding), do: binding.last_seen_at || binding.activated_at
  defp activity_at(binding), do: binding.enroll_expires_at

  defp timestamp(%{status: :revoked} = binding),
    do: "Revoked #{Format.relative(binding.revoked_at)}"

  defp timestamp(%{status: :active, last_seen_at: nil} = binding),
    do: "Linked #{Format.relative(binding.activated_at)}"

  defp timestamp(%{status: :active} = binding),
    do: "Seen #{Format.relative(binding.last_seen_at)}"

  defp timestamp(binding), do: "Code expires #{Format.relative(binding.enroll_expires_at)}"

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
