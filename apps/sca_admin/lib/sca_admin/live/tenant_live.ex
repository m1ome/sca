defmodule ScaAdmin.TenantLive do
  @moduledoc """
  One merchant: how they are configured, how much they use us, and the switch
  that stops serving them.

  The signing key is not shown. Support does not need it, and an internal
  console that displays a merchant's secret is a breach waiting for a screenshot.
  """

  use ScaAdmin, :live_view

  alias Sca.Actions
  alias Sca.Models.Request
  alias Sca.Repos.BindingRepo
  alias Sca.Repos.RequestRepo
  alias Sca.Repos.TenantRepo
  alias Sca.Repos.UserRepo

  @impl true
  def mount(%{"id" => public_id}, _session, socket) do
    case TenantRepo.get_by_public_id(public_id) do
      {:ok, tenant} ->
        {:ok,
         socket |> assign(page_title: tenant.name, confirming: false) |> assign_tenant(tenant)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That merchant does not exist.")
         |> push_navigate(to: ~p"/tenants")}
    end
  end

  @impl true
  def handle_event("confirm-suspend", _params, socket),
    do: {:noreply, assign(socket, confirming: true)}

  def handle_event("cancel-suspend", _params, socket),
    do: {:noreply, assign(socket, confirming: false)}

  def handle_event("suspend", _params, socket) do
    case Actions.Tenant.deactivate(socket.assigns.tenant) do
      {:ok, tenant} ->
        {:noreply,
         socket
         |> assign(confirming: false)
         |> put_flash(:info, "Merchant suspended.")
         |> assign_tenant(tenant)}

      {:error, _changeset} ->
        {:noreply, socket |> assign(confirming: false) |> put_flash(:error, "Could not suspend.")}
    end
  end

  def handle_event("activate", _params, socket) do
    case Actions.Tenant.activate(socket.assigns.tenant) do
      {:ok, tenant} ->
        {:noreply,
         socket |> put_flash(:info, "Merchant is being served again.") |> assign_tenant(tenant)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not activate.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_admin={@current_admin} active="Tenants">
      <.link
        navigate={~p"/tenants"}
        class="mb-4 inline-flex items-center gap-2 text-xs font-semibold text-muted hover:text-ink"
      >
        <.icon name="hero-arrow-left" class="h-4 w-4" /> Tenants
      </.link>

      <.page_header
        eyebrow={@tenant.public_id}
        title={@tenant.name}
        description="Merchant on this cluster."
      >
        <:action>
          <.button :if={@tenant.status == :active} variant="secondary" phx-click="confirm-suspend">
            Suspend merchant
          </.button>
          <.button :if={@tenant.status == :suspended} variant="secondary" phx-click="activate">
            Resume merchant
          </.button>
        </:action>
      </.page_header>

      <div class="mb-4 grid gap-4 sm:grid-cols-3">
        <.metric label="Team members" value={@members} />
        <.metric label="Active devices" value={@bindings} />
        <.metric label="Waiting for a decision" value={@pending} />
      </div>

      <div class="grid items-stretch gap-4 lg:grid-cols-2">
        <.surface>
          <.list_header
            title="Recent approvals"
            description="The last requests this merchant raised."
          />

          <.table id="tenant-approvals" rows={@requests}>
            <:col :let={request} label="Request">
              <p class="truncate font-medium">{request.title}</p>
              <p class="truncate text-xs text-muted">
                {String.capitalize(to_string(request.type))}
              </p>
            </:col>
            <:col :let={request} label="State" width="w-32">
              <.status value={request.status} />
            </:col>
            <:col :let={request} label="When" width="w-40" hide_below="sm">
              <span class="text-muted" title={Format.datetime(request.inserted_at)}>
                {Format.relative(request.inserted_at)}
              </span>
            </:col>
          </.table>

          <.empty_state :if={@requests == []} title="Nothing raised yet" />
        </.surface>

        <.surface>
          <.list_header title="Configuration" description="What support usually needs to know." />
          <dl>
            <.field label="Status"><.status value={@tenant.status} /></.field>
            <.field label="Webhook">
              <span class="truncate">{@tenant.settings.webhook_url || "—"}</span>
            </.field>
            <.field label="Encryption">
              {configured?(@tenant.settings.webhook_certificate)}
            </.field>
            <.field label="Signing key">{configured?(@tenant.settings.webhook_secret)}</.field>
            <.field label="Approval timeout">
              {@tenant.settings.default_request_timeout_seconds}s
            </.field>
            <.field label="Joined">{Format.datetime(@tenant.inserted_at)}</.field>
          </dl>
        </.surface>
      </div>

      <.modal
        :if={@confirming}
        id="suspend-tenant"
        show
        on_cancel={JS.push("cancel-suspend")}
        title="Suspend this merchant?"
        description="They stop being served until someone here resumes them."
      >
        <p class="text-sm leading-6 text-muted">
          Nothing is deleted and no device is revoked: their data, bindings and audit trail
          stay exactly as they are. New approvals simply stop being accepted.
        </p>

        <:footer>
          <.button variant="secondary" phx-click="cancel-suspend">Keep serving</.button>
          <.button phx-click="suspend">Suspend merchant</.button>
        </:footer>
      </.modal>
    </Layouts.app>
    """
  end

  defp assign_tenant(socket, tenant) do
    requests = tenant |> RequestRepo.list_by_tenant() |> Enum.take(5)

    assign(socket,
      tenant: tenant,
      requests: requests,
      members: length(UserRepo.list_by_tenant(tenant)),
      bindings: length(BindingRepo.list_active(tenant)),
      pending: Enum.count(RequestRepo.list_by_tenant(tenant), &Request.pending?/1)
    )
  end

  defp configured?(value) when is_binary(value) and value != "", do: "Configured"
  defp configured?(_value), do: "Not set"

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp metric(assigns) do
    ~H"""
    <div class="rounded-xl border border-line bg-white px-5 py-5 shadow-surface">
      <span class="text-xs text-muted">{@label}</span>
      <b class="mt-2 block text-2xl font-semibold tracking-tight text-ink">{@value}</b>
    </div>
    """
  end
end
