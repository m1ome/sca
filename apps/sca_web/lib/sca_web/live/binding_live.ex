defmodule ScaWeb.BindingLive do
  @moduledoc """
  One device: who it belongs to, what it has been asked lately, and the button
  that takes it out of service.

  Revoking is the consequential action, so it lives here rather than in the
  list — and it says what it costs before it happens.
  """

  use ScaWeb, :live_view

  alias Sca.Actions
  alias Sca.Repos.RequestRepo
  alias Sca.Scope

  @recent_approvals 5

  @impl true
  def mount(%{"id" => public_id}, _session, socket) do
    case Scope.fetch_binding(socket.assigns.current_scope, public_id) do
      {:ok, binding} ->
        {:ok,
         socket |> assign(page_title: name(binding), confirming: false) |> assign_binding(binding)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That device does not exist.")
         |> push_navigate(to: ~p"/bindings")}
    end
  end

  @impl true
  def handle_event("confirm-revoke", _params, socket) do
    {:noreply, assign(socket, confirming: true)}
  end

  def handle_event("cancel-revoke", _params, socket) do
    {:noreply, assign(socket, confirming: false)}
  end

  def handle_event("revoke", _params, socket) do
    case Actions.Binding.revoke(socket.assigns.binding) do
      {:ok, binding} ->
        {:noreply,
         socket
         |> assign(confirming: false)
         |> put_flash(:info, "Device revoked. It can no longer confirm anything.")
         |> assign_binding(binding)}

      {:error, _reason} ->
        {:noreply,
         socket |> assign(confirming: false) |> put_flash(:error, "Could not revoke this device.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_tenant={@current_tenant}
      active="Bindings"
    >
      <.link
        navigate={~p"/bindings"}
        class="mb-4 inline-flex items-center gap-2 text-xs font-semibold text-muted hover:text-ink"
      >
        <.icon name="hero-arrow-left" class="h-4 w-4" /> Bindings
      </.link>

      <.page_header
        eyebrow={@binding.public_id}
        title={name(@binding)}
        description={"Linked to #{@binding.external_id}."}
      >
        <:action>
          <.button :if={@binding.status != :revoked} variant="danger" phx-click="confirm-revoke">
            Revoke device
          </.button>
        </:action>
      </.page_header>

      <div class="grid items-start gap-4 lg:grid-cols-[minmax(0,1fr)_320px]">
        <.surface>
          <.list_header
            title="Recent approvals"
            description="What this device has been asked lately."
          />

          <.table id="binding-requests" rows={@requests}>
            <:col :let={request} label="ID" width="w-28" hide_below="sm">
              <span class="font-mono text-xs text-muted">{request.public_id}</span>
            </:col>
            <:col :let={request} label="Request">
              <p class="truncate font-medium">{request.title}</p>
              <p class="truncate text-xs text-muted">{String.capitalize(to_string(request.type))}</p>
            </:col>
            <:col :let={request} label="State" width="w-32">
              <.status value={request.status} />
            </:col>
            <:col :let={request} label="When" width="w-44" hide_below="sm">
              <span class="text-muted" title={Format.datetime(request.inserted_at)}>
                {Format.relative(request.inserted_at)}
              </span>
            </:col>
            <:action :let={request}>
              <.row_action navigate={~p"/approvals/#{request.public_id}"} />
            </:action>
          </.table>

          <.empty_state
            :if={@requests == []}
            title="Nothing asked of this device yet"
            description="Approvals raised for it will appear here."
          />
        </.surface>

        <div class="space-y-4">
          <.surface>
            <.list_header title="Device" />
            <dl>
              <.field label="State"><.status value={@binding.status} /></.field>
              <.field label="Platform">{platform(@binding)}</.field>
              <.field label="Attested">{if @binding.attested, do: "Yes", else: "No"}</.field>
              <.field label="Linked">{Format.datetime(@binding.activated_at)}</.field>
              <.field :if={@binding.revoked_at} label="Revoked">
                {Format.datetime(@binding.revoked_at)}
              </.field>
              <.field label="Last seen">{Format.datetime(@binding.last_seen_at)}</.field>
            </dl>
          </.surface>

          <.surface :if={@binding.status == :pending}>
            <.list_header
              title="Waiting for a scan"
              description="The activation code is still good."
            />
            <div class="flex flex-col items-center gap-3 px-5 py-5">
              <div class="rounded-xl border border-line bg-white p-3">
                {Phoenix.HTML.raw(ScaWeb.Enrollment.qr_code(@current_tenant, @binding, 200))}
              </div>
              <p class="text-center text-xs text-muted">
                Expires {Format.relative(@binding.enroll_expires_at)},
                at {Format.datetime(@binding.enroll_expires_at)}
              </p>
            </div>

            <dl>
              <.field label="Server address">
                <span class="break-all font-mono text-xs">
                  {ScaWeb.Enrollment.connect_url(@current_tenant)}
                </span>
              </.field>
              <.field label="Code">
                <span class="break-all font-mono text-xs">{@binding.enroll_token}</span>
              </.field>
            </dl>
          </.surface>
        </div>
      </div>

      <.modal
        :if={@confirming}
        id="revoke-binding"
        show
        on_cancel={JS.push("cancel-revoke")}
        title="Revoke this device?"
        description="It stops being able to confirm anything, immediately and for good."
      >
        <p class="text-sm leading-6 text-muted">
          The session dies with it, so the phone is signed out the moment you confirm.
          Approvals already answered keep their proof. To link this user again, create a
          new binding and let them scan a fresh code.
        </p>

        <:footer>
          <.button variant="secondary" phx-click="cancel-revoke">Keep device</.button>
          <.button variant="danger" phx-click="revoke">Revoke device</.button>
        </:footer>
      </.modal>
    </Layouts.app>
    """
  end

  defp assign_binding(socket, binding) do
    requests = binding |> RequestRepo.list_by_binding() |> Enum.take(@recent_approvals)

    assign(socket, binding: binding, requests: requests)
  end

  defp name(binding) do
    case String.trim(to_string(binding.name)) do
      "" -> "Unnamed device"
      name -> name
    end
  end

  defp platform(%{push_platform: nil}), do: "—"
  defp platform(%{push_platform: platform}), do: platform |> to_string() |> String.upcase()
end
