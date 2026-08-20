defmodule ScaWeb.BindingsLive do
  @moduledoc """
  The devices a merchant has linked, and the modal that links a new one.

  Enrolling produces an activation code with a deadline — the thing that goes
  into the QR the phone scans. It is shown once, here, because it is the only
  moment anyone will see it.
  """

  use ScaWeb, :live_view

  alias Sca.Actions
  alias Sca.Models.Binding
  alias Sca.Repos.BindingRepo

  @statuses Ecto.Enum.values(Binding, :status)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Bindings", status_options: status_options())
     |> assign(modal: :closed, form: enrollment_form(), activation: nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {bindings, meta} = BindingRepo.page_for_tenant(socket.assigns.current_tenant, flop(params))

    {:noreply,
     socket
     |> assign(status: params["status"] || "", meta: meta)
     |> stream(:bindings, bindings, reset: true)}
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    {:noreply, push_patch(socket, to: ~p"/bindings?#{query(status, 1)}")}
  end

  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: ~p"/bindings?#{query(socket.assigns.status, page)}")}
  end

  def handle_event("new", _params, socket) do
    {:noreply, assign(socket, modal: :form, form: enrollment_form(), activation: nil)}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, modal: :closed, activation: nil)}
  end

  def handle_event("enroll", %{"binding" => params}, socket) do
    case Actions.Binding.enroll(socket.assigns.current_tenant, params) do
      {:ok, binding} ->
        {:noreply,
         socket
         |> assign(modal: :activation, activation: binding)
         |> stream_insert(:bindings, binding, at: 0)}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :binding))}
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
      <.page_header
        eyebrow="Linked devices"
        title="Bindings"
        description="The phones that can confirm approvals for your users."
      >
        <:action>
          <.button phx-click="new">
            <.icon name="hero-plus" class="h-4 w-4" /> New binding
          </.button>
        </:action>
      </.page_header>

      <form phx-change="filter" class="mb-4 max-w-xs">
        <.input
          type="select"
          name="status"
          value={@status}
          label="State"
          prompt="All states"
          options={@status_options}
        />
      </form>

      <.surface>
        <.list_header title="Devices" description={"#{@meta.total_count} in total"} />

        <.table id="bindings" rows={@streams.bindings} stream>
          <:col :let={binding} label="Device">
            <p class="truncate font-medium">{device_name(binding)}</p>
            <p class="truncate text-xs text-muted">{binding.external_id}</p>
          </:col>
          <:col :let={binding} label="Platform" width="w-28" hide_below="sm">
            <span class="text-muted">{platform(binding)}</span>
          </:col>
          <:col :let={binding} label="State" width="w-32">
            <.status value={binding.status} />
          </:col>
          <:col :let={binding} label="Activity" width="w-52" hide_below="md">
            <span class="text-muted" title={Format.datetime(activity_at(binding))}>
              {activity(binding)}
            </span>
          </:col>
          <:action :let={binding}>
            <.link
              navigate={~p"/bindings/#{binding.public_id}"}
              class="text-sm font-semibold text-brand hover:text-brand-strong"
            >
              View
            </.link>
          </:action>
        </.table>

        <.empty_state
          :if={@meta.total_count == 0}
          title="No devices linked yet"
          description="Create a binding to get an activation code for the phone to scan."
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
        id="new-binding"
        show
        on_cancel={JS.push("close")}
        title="New binding"
        description="Link a device to one of your users."
      >
        <.form :let={f} for={@form} id="enrollment-form" phx-submit="enroll" class="space-y-4">
          <.input
            field={f[:external_id]}
            label="Your reference for the user"
            placeholder="customer-4471"
            help="However you identify this person on your side. Re-enrolling the same reference replaces their device."
            required
          />
          <.input field={f[:name]} label="Device name" placeholder="Dana's iPhone" />
        </.form>

        <:footer>
          <.button variant="secondary" phx-click="close">Cancel</.button>
          <.button type="submit" form="enrollment-form">Create binding</.button>
        </:footer>
      </.modal>

      <.modal
        :if={@modal == :activation}
        id="activation-code"
        show
        on_cancel={JS.push("close")}
        title="Activation code"
        description="Show this to the device. It works once, and only until it expires."
      >
        <div class="flex flex-col items-center gap-4">
          <div class="rounded-xl border border-line bg-white p-3">
            {Phoenix.HTML.raw(ScaWeb.Enrollment.qr_code(@current_tenant, @activation))}
          </div>

          <p class="text-xs text-muted">
            Open the app and scan this. Expires {Format.relative(@activation.enroll_expires_at)},
            at {Format.datetime(@activation.enroll_expires_at)}.
          </p>

          <details class="w-full">
            <summary class="cursor-pointer text-xs font-semibold text-brand">
              Cannot scan it?
            </summary>
            <p class="mt-2 text-xs text-muted">
              The app takes the same thing typed in: the address it should bind
              to, and the code.
            </p>
            <dl class="mt-2 rounded-lg border border-line">
              <.field label="Server address">
                <.copy_value
                  id="connect-url"
                  value={ScaWeb.Enrollment.connect_url(@current_tenant)}
                  title="Copy server address"
                  class="font-mono text-xs"
                />
              </.field>
              <.field label="Code">
                <.copy_value
                  id="activation-token"
                  value={@activation.enroll_token}
                  title="Copy activation code"
                  class="font-mono text-xs"
                />
              </.field>
            </dl>
          </details>
        </div>

        <p class="mt-3 text-center text-xs text-muted">Binding {@activation.public_id}</p>

        <:footer>
          <.button phx-click="close">Done</.button>
        </:footer>
      </.modal>
    </Layouts.app>
    """
  end

  defp device_name(binding) do
    case String.trim(to_string(binding.name)) do
      "" -> "Unnamed device"
      name -> name
    end
  end

  defp platform(%{push_platform: nil}), do: "—"
  defp platform(%{push_platform: platform}), do: platform |> to_string() |> String.upcase()

  # A device's most recent fact: how long its code is still good for, when it
  # was cut off, or when it was linked.
  defp activity_at(%{status: :pending} = binding), do: binding.enroll_expires_at
  defp activity_at(%{status: :revoked} = binding), do: binding.revoked_at
  defp activity_at(binding), do: binding.last_seen_at || binding.activated_at

  defp activity(%{status: :pending} = binding) do
    if Timex.after?(binding.enroll_expires_at, Timex.now()) do
      "Code expires #{Format.relative(binding.enroll_expires_at)}"
    else
      "Code expired"
    end
  end

  defp activity(%{status: :revoked} = binding),
    do: "Revoked #{Format.relative(binding.revoked_at)}"

  defp activity(%{last_seen_at: nil} = binding),
    do: "Linked #{Format.relative(binding.activated_at)}"

  defp activity(binding), do: "Seen #{Format.relative(binding.last_seen_at)}"

  defp enrollment_form, do: to_form(%{"external_id" => "", "name" => ""}, as: :binding)

  defp status_options do
    Enum.map(@statuses, fn status -> {status |> to_string() |> String.capitalize(), status} end)
  end

  defp flop(params) do
    %{"page" => params["page"] || 1, "page_size" => 20, "filters" => filters(params["status"])}
  end

  defp filters(status) when status in [nil, ""], do: []
  defp filters(status), do: [%{"field" => "status", "op" => "==", "value" => status}]

  defp query(status, page) do
    %{"status" => status, "page" => page}
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
  end
end
