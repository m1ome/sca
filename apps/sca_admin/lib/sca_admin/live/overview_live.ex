defmodule ScaAdmin.OverviewLive do
  @moduledoc "What the whole platform looks like right now, across every merchant."

  use ScaAdmin, :live_view

  alias Sca.Models.Binding
  alias Sca.Models.Request
  alias Sca.Models.WebhookDelivery
  alias Sca.Repo

  import Ecto.Query

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Overview",
       tenants: count(Sca.Models.Tenant),
       bindings: count(where(Binding, status: :active)),
       pending: count(where(Request, status: :pending)),
       failed: count(where(WebhookDelivery, status: :failed))
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_admin={@current_admin} active="Overview">
      <.page_header
        eyebrow="Platform"
        title="Overview"
        description="Every merchant on this cluster, at a glance."
      />

      <div class="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <.metric label="Merchants" value={@tenants} path={~p"/tenants"} />
        <.metric label="Active devices" value={@bindings} path={~p"/bindings"} />
        <.metric label="Waiting for a decision" value={@pending} path={~p"/approvals"} />
        <.metric label="Failed deliveries" value={@failed} />
      </div>

      <.surface>
        <.list_header title="Where to look" description="The lists behind those numbers." />
        <.row>
          <div class="min-w-0 flex-1">
            <p class="text-sm font-semibold text-ink">Merchants</p>
            <p class="mt-0.5 text-xs text-muted">Tenants, their settings and their teams.</p>
          </div>
          <.link
            navigate={~p"/tenants"}
            class="text-sm font-semibold text-brand hover:text-brand-strong"
          >
            Open
          </.link>
        </.row>
        <.row>
          <div class="min-w-0 flex-1">
            <p class="text-sm font-semibold text-ink">Approvals</p>
            <p class="mt-0.5 text-xs text-muted">Every request raised on the platform.</p>
          </div>
          <.link
            navigate={~p"/approvals"}
            class="text-sm font-semibold text-brand hover:text-brand-strong"
          >
            Open
          </.link>
        </.row>
      </.surface>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :path, :string, default: nil

  defp metric(assigns) do
    ~H"""
    <div class="rounded-xl border border-line bg-white px-5 py-5 shadow-surface">
      <span class="text-xs text-muted">{@label}</span>
      <b class="mt-2 block text-2xl font-semibold tracking-tight text-ink">{@value}</b>
      <.link :if={@path} navigate={@path} class="mt-2 inline-block text-xs font-semibold text-brand">
        View
      </.link>
    </div>
    """
  end

  defp count(queryable), do: Repo.aggregate(queryable, :count)
end
