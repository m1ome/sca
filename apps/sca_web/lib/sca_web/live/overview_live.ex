defmodule ScaWeb.OverviewLive do
  @moduledoc """
  Where a merchant lands: how many devices are bound, and what is waiting for
  someone to confirm it.
  """

  use ScaWeb, :live_view

  alias Sca.Models.Request
  alias Sca.Repos.BindingRepo
  alias Sca.Repos.RequestRepo

  @impl true
  def mount(_params, _session, socket) do
    tenant = socket.assigns.current_tenant
    requests = RequestRepo.list_by_tenant(tenant)

    {:ok,
     assign(socket,
       page_title: "Overview",
       bindings: length(BindingRepo.list_active(tenant)),
       pending: Enum.count(requests, &Request.pending?/1),
       total: length(requests)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_tenant={@current_tenant}
      active="Overview"
    >
      <.page_header
        eyebrow="Console"
        title={"Good to see you, #{@current_user.name}"}
        description="Strong customer authentication for your merchant, at a glance."
      />

      <div class="mb-6 grid gap-4 sm:grid-cols-3">
        <.metric label="Active bindings" value={@bindings} />
        <.metric label="Waiting for a decision" value={@pending} />
        <.metric label="Approvals in total" value={@total} />
      </div>

      <.surface>
        <.list_header title="Next steps" description="What this console can do today." />
        <.row>
          <div class="min-w-0 flex-1">
            <p class="text-sm font-semibold text-ink">Approvals</p>
            <p class="mt-0.5 text-xs text-muted">Everything raised through the API, with status.</p>
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

  defp metric(assigns) do
    ~H"""
    <div class="rounded-xl border border-line bg-white px-5 py-5 shadow-surface">
      <span class="text-xs text-muted">{@label}</span>
      <b class="mt-2 block text-2xl font-semibold tracking-tight text-ink">{@value}</b>
    </div>
    """
  end
end
