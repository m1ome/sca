defmodule ScaWeb.TeamMemberLive do
  @moduledoc """
  One member: their role, whether they can still sign in, and a way back in
  when they have lost their password.

  Everything here changes what somebody can do, which is why none of it lives
  in the list.
  """

  use ScaWeb, :live_view

  alias Sca.Actions
  alias Sca.Models.User
  alias Sca.Scope

  @roles Ecto.Enum.values(User, :role)

  @impl true
  def mount(%{"id" => public_id}, _session, socket) do
    case Scope.fetch_user(socket.assigns.current_scope, public_id) do
      {:ok, member} ->
        {:ok,
         socket
         |> assign(page_title: display_name(member), role_options: options(@roles))
         |> assign(member: member, password: nil)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That member does not exist.")
         |> push_navigate(to: ~p"/team")}
    end
  end

  @impl true
  def handle_event("role", %{"role" => role}, socket) do
    case Actions.Tenant.change_user_role(socket.assigns.member, role) do
      {:ok, member} ->
        {:noreply, socket |> assign(member: member) |> put_flash(:info, "Role updated.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not change that role.")}
    end
  end

  def handle_event("disable", _params, socket) do
    update_status(socket, &Actions.Tenant.disable_user/1, "Member disabled.")
  end

  def handle_event("enable", _params, socket) do
    update_status(socket, &Actions.Tenant.enable_user/1, "Member can sign in again.")
  end

  def handle_event("reset-password", _params, socket) do
    case Actions.Tenant.reset_user_password(socket.assigns.member) do
      {:ok, %{user: member, password: password}} ->
        {:noreply, assign(socket, member: member, password: password)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not reset that password.")}
    end
  end

  def handle_event("close", _params, socket), do: {:noreply, assign(socket, password: nil)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_tenant={@current_tenant}
      active="Team"
    >
      <.link
        navigate={~p"/team"}
        class="mb-4 inline-flex items-center gap-2 text-xs font-semibold text-muted hover:text-ink"
      >
        <.icon name="hero-arrow-left" class="h-4 w-4" /> Team
      </.link>

      <.page_header
        eyebrow={@member.public_id}
        title={display_name(@member)}
        description={@member.email}
      >
        <:action>
          <.button
            :if={@member.status == :active}
            variant="secondary"
            phx-click="disable"
            disabled={yourself?(@member, @current_user)}
          >
            Disable access
          </.button>
          <.button :if={@member.status == :disabled} variant="secondary" phx-click="enable">
            Enable access
          </.button>
        </:action>
      </.page_header>

      <div class="grid max-w-4xl items-start gap-4 lg:grid-cols-2">
        <.surface>
          <.list_header
            title="Role"
            description="What this person may do in the console."
          />

          <form phx-change="role" class="px-5 py-5">
            <.input
              type="select"
              name="role"
              value={@member.role}
              label="Role"
              options={@role_options}
              disabled={yourself?(@member, @current_user)}
              help={
                if yourself?(@member, @current_user),
                  do: "You cannot change your own role.",
                  else: "Owners manage the team; viewers only read."
              }
            />
          </form>
        </.surface>

        <div class="space-y-4">
          <.surface>
            <.list_header title="Access" />
            <dl>
              <.field label="Status"><.status value={@member.status} /></.field>
              <.field label="Added">{Format.datetime(@member.inserted_at)}</.field>
            </dl>
          </.surface>

          <.surface>
            <.list_header
              title="Password"
              description="Issue a new one if they cannot sign in."
            />
            <div class="px-5 py-4">
              <.button variant="secondary" phx-click="reset-password" class="w-full">
                Reset password
              </.button>
            </div>
          </.surface>
        </div>
      </div>

      <.modal
        :if={@password}
        id="new-password"
        show
        on_cancel={JS.push("close")}
        title="New password"
        description="Shown once. Hand it over and have them change it."
      >
        <p class="text-sm text-ink">{@member.email}</p>

        <div class="mt-3 rounded-xl border border-line bg-canvas px-4 py-4 text-center">
          <p id="reset-password-value" class="break-all font-mono text-sm font-semibold text-ink">
            {@password}
          </p>
        </div>

        <:footer>
          <.button
            variant="secondary"
            phx-click={JS.dispatch("sca:copy", to: "#reset-password-value")}
          >
            Copy password
          </.button>
          <.button phx-click="close">Done</.button>
        </:footer>
      </.modal>
    </Layouts.app>
    """
  end

  defp update_status(socket, action, message) do
    case action.(socket.assigns.member) do
      {:ok, member} ->
        {:noreply, socket |> assign(member: member) |> put_flash(:info, message)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not change that member.")}
    end
  end

  # An owner locking themselves out is a support ticket, not a feature.
  defp yourself?(member, current_user), do: member.id == current_user.id

  defp display_name(member) do
    case String.trim(to_string(member.name)) do
      "" -> member.email |> String.split("@") |> hd()
      name -> name
    end
  end

  defp options(values) do
    Enum.map(values, fn value -> {value |> to_string() |> String.capitalize(), value} end)
  end
end
