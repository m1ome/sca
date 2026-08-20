defmodule ScaWeb.ApprovalLive do
  @moduledoc """
  One approval, in full: what the device was asked, how it answered, and the
  proof it signed.

  The consequential action here is cancelling — a merchant cannot approve on
  their user's behalf, that is the whole point of the product. What they can do
  is take the question back.
  """

  use ScaWeb, :live_view

  alias Sca.Actions
  alias Sca.Models.Request
  alias Sca.Repos.BindingRepo
  alias Sca.Scope

  @impl true
  def mount(%{"id" => public_id}, _session, socket) do
    case Scope.fetch_request(socket.assigns.current_scope, public_id) do
      {:ok, request} ->
        {:ok, socket |> assign(page_title: request.title) |> assign_request(request)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That approval does not exist.")
         |> push_navigate(to: ~p"/approvals")}
    end
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    case Actions.Request.cancel(socket.assigns.request) do
      {:ok, request} ->
        {:noreply, socket |> put_flash(:info, "Approval cancelled.") |> assign_request(request)}

      {:error, :not_pending} ->
        {:noreply, put_flash(socket, :error, "This approval has already been answered.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not cancel this approval.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_tenant={@current_tenant}
      active="Approvals"
    >
      <.link
        navigate={~p"/approvals"}
        class="mb-4 inline-flex items-center gap-2 text-xs font-semibold text-muted hover:text-ink"
      >
        <.icon name="hero-arrow-left" class="h-4 w-4" /> Approvals
      </.link>

      <.page_header
        eyebrow={@request.public_id}
        title={@request.title}
        description={@request.description}
      >
        <:action>
          <.button :if={Request.pending?(@request)} variant="secondary" phx-click="cancel">
            Cancel approval
          </.button>
        </:action>
      </.page_header>

      <div class="grid items-stretch gap-4 lg:grid-cols-2">
        <.surface>
          <.list_header title="What the user was asked to confirm" />
          <dl>
            <.field :for={{key, value} <- @request.payload} label={key}>
              <span class="truncate">{value}</span>
            </.field>
          </dl>
          <.empty_state :if={@request.payload == %{}} title="This card carried no parameters" />
        </.surface>

        <.surface>
          <.list_header title="Status" />
          <dl>
            <.field label="Current"><.status value={@request.status} /></.field>
            <.field label="Type">{@request.type}</.field>
            <.field label="Device"><span class="truncate">{device(@binding)}</span></.field>
            <.field label="Raised">{Format.datetime(@request.inserted_at)}</.field>
            <.field label={if @request.decided_at, do: "Answered", else: "Expires"}>
              {Format.datetime(@request.decided_at || @request.expires_at)}
            </.field>
          </dl>
        </.surface>
      </div>

      <.surface :if={@request.signature} class="mt-4">
        <.list_header title="Proof" description="Check it yourself against the device's public key." />
        <dl>
          <.field label="Signed string">
            <span class="break-all font-mono text-xs">{@request.signed_payload}</span>
          </.field>
          <.field label="Signature">
            <span class="break-all font-mono text-xs">{@request.signature}</span>
          </.field>
        </dl>
      </.surface>
    </Layouts.app>
    """
  end

  defp assign_request(socket, request) do
    {:ok, binding} = BindingRepo.get(request.binding_id)

    assign(socket, request: request, binding: binding)
  end

  defp device(binding) do
    case String.trim(to_string(binding.name)) do
      "" -> binding.external_id
      name -> "#{name} · #{binding.external_id}"
    end
  end
end
