defmodule ScaAdmin.TenantsLive do
  @moduledoc """
  Every merchant on the platform, and the form that onboards one.

  Onboarding creates the merchant together with the person who will run it:
  a tenant nobody can sign into is a dead end. Their password is shown once,
  here, because this is the only moment anyone will see it.
  """

  use ScaAdmin, :live_view

  alias Sca.Actions
  alias Sca.Repos.TenantRepo
  alias ScaUi.PublicUrl

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Tenants",
       modal: :closed,
       form: onboarding_form(),
       credentials: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {tenants, meta} = TenantRepo.list(%{"page" => params["page"] || 1, "page_size" => 20})

    {:noreply, socket |> assign(meta: meta) |> stream(:tenants, tenants, reset: true)}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: ~p"/tenants?page=#{page}")}
  end

  def handle_event("new", _params, socket) do
    {:noreply, assign(socket, modal: :form, form: onboarding_form(), credentials: nil)}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, modal: :closed, credentials: nil)}
  end

  def handle_event("onboard", %{"tenant" => params}, socket) do
    case Actions.Tenant.create(params) do
      {:ok, onboarding} ->
        {:noreply,
         socket
         |> assign(modal: :credentials, credentials: onboarding)
         |> stream_insert(:tenants, onboarding.tenant, at: 0)}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :tenant))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_admin={@current_admin} active="Tenants">
      <.page_header
        eyebrow="Platform"
        title="Tenants"
        description="The merchants using strong customer authentication here."
      >
        <:action>
          <.button phx-click="new">
            <.icon name="hero-plus" class="h-4 w-4" /> New merchant
          </.button>
        </:action>
      </.page_header>

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

        <.empty_state
          :if={@meta.total_count == 0}
          title="No merchants yet"
          description="Onboard one to give it a console, devices and an API key."
        />
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
      <.modal
        :if={@modal == :form}
        id="new-tenant"
        show
        on_cancel={JS.push("close")}
        title="New merchant"
        description="The merchant and the person who will run its console."
      >
        <.form :let={f} for={@form} id="tenant-form" phx-submit="onboard" class="space-y-4">
          <.input field={f[:name]} label="Merchant name" placeholder="Northstar Payments" required />
          <.input
            field={f[:owner_email]}
            type="email"
            label="Owner email"
            placeholder="ops@northstar.com"
            help="They sign in with this, the merchant id and the password we generate."
            required
          />
          <.input field={f[:owner_name]} label="Owner name" placeholder="Dana Reeves" />
        </.form>

        <:footer>
          <.button variant="secondary" phx-click="close">Cancel</.button>
          <.button type="submit" form="tenant-form">Onboard merchant</.button>
        </:footer>
      </.modal>

      <.modal
        :if={@modal == :credentials}
        id="tenant-credentials"
        show
        on_cancel={JS.push("close")}
        title="How they sign in"
        description="Shown once. We keep the hash, never the password itself."
      >
        <dl>
          <.field label="Console">{console_url()}</.field>
          <.field label="Merchant id">{@credentials.tenant.public_id}</.field>
          <.field label="Email">
            <span class="truncate">{@credentials.user.email}</span>
          </.field>
          <.field label="Password">
            <.copy_value
              id="owner-password"
              value={@credentials.password}
              title="Copy password"
              class="font-mono text-xs"
            />
          </.field>
        </dl>

        <:footer>
          <.button navigate={~p"/tenants/#{@credentials.tenant.public_id}"}>
            Open merchant
          </.button>
        </:footer>
      </.modal>
    </Layouts.app>
    """
  end

  defp console_url, do: PublicUrl.of(:sca_web, ScaWeb.Endpoint)

  defp onboarding_form do
    to_form(%{"name" => "", "owner_email" => "", "owner_name" => ""}, as: :tenant)
  end

  defp webhook(%{settings: %{webhook_url: url}}) when is_binary(url) and url != "",
    do: "Webhook set"

  defp webhook(_tenant), do: "No webhook"
end
