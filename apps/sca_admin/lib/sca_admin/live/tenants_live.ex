defmodule ScaAdmin.TenantsLive do
  @moduledoc "Every merchant on the platform."

  use ScaAdmin, :live_view

  alias Sca.Repos.TenantRepo

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, page_title: "Tenants")}

  @impl true
  def handle_params(params, _uri, socket) do
    {tenants, meta} = TenantRepo.list(%{"page" => params["page"] || 1, "page_size" => 20})

    {:noreply, socket |> assign(meta: meta) |> stream(:tenants, tenants, reset: true)}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: ~p"/tenants?page=#{page}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_admin={@current_admin} active="Tenants">
      <.page_header
        eyebrow="Platform"
        title="Tenants"
        description="The merchants using strong customer authentication here."
      />

      <.surface>
        <.list_header title="Merchants" description={"#{@meta.total_count} in total"} />

        <.table id="tenants" rows={@streams.tenants} stream>
          <:col :let={tenant} label="Merchant">
            <.link
              navigate={~p"/tenants/#{tenant.public_id}"}
              class="truncate font-medium text-brand hover:underline"
            >
              {tenant.name}
            </.link>
            <p class="truncate text-xs text-muted">{tenant.public_id}</p>
          </:col>
          <:col :let={tenant} label="Webhook" width="w-44" hide_below="md">
            <span class="text-muted">{webhook(tenant)}</span>
          </:col>
          <:col :let={tenant} label="State" width="w-32">
            <.status value={tenant.status} />
          </:col>
          <:col :let={tenant} label="Onboarded" width="w-44" hide_below="md">
            <span class="text-muted" title={Format.datetime(tenant.inserted_at)}>
              {Format.relative(tenant.inserted_at)}
            </span>
          </:col>
          <:action :let={tenant}>
            <.link
              navigate={~p"/tenants/#{tenant.public_id}"}
              class="text-sm font-semibold text-brand hover:text-brand-strong"
            >
              View
            </.link>
          </:action>
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

  defp webhook(%{settings: %{webhook_url: url}}) when is_binary(url) and url != "",
    do: "Webhook set"

  defp webhook(_tenant), do: "No webhook"
end
