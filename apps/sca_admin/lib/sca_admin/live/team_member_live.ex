defmodule ScaAdmin.TeamMemberLive do
  @moduledoc "One staff account: role, access and a way back in."

  use ScaAdmin, :live_view

  alias Sca.Actions
  alias Sca.Models.Admin
  alias Sca.Repos.AdminRepo

  @roles Ecto.Enum.values(Admin, :role)

  @impl true
  def mount(%{"id" => public_id}, _session, socket) do
    case AdminRepo.get_by_public_id(public_id) do
      {:ok, admin} ->
        {:ok,
         socket
         |> assign(page_title: display_name(admin), role_options: options(@roles))
         |> assign(admin: admin, password: nil)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That account does not exist.")
         |> push_navigate(to: ~p"/team")}
    end
  end

  @impl true
  def handle_event("role", %{"role" => role}, socket) do
    case Actions.Admin.change_role(socket.assigns.admin, role) do
      {:ok, admin} ->
        {:noreply, socket |> assign(admin: admin) |> put_flash(:info, "Role updated.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not change that role.")}
    end
  end

  def handle_event("disable", _params, socket) do
    apply_change(socket, &Actions.Admin.disable/1, "Access disabled.")
  end

  def handle_event("enable", _params, socket) do
    apply_change(socket, &Actions.Admin.enable/1, "Access restored.")
  end

  def handle_event("reset-password", _params, socket) do
    case Actions.Admin.reset_password(socket.assigns.admin) do
      {:ok, %{admin: admin, password: password}} ->
        {:noreply, assign(socket, admin: admin, password: password)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not reset that password.")}
    end
  end

  def handle_event("close", _params, socket), do: {:noreply, assign(socket, password: nil)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_admin={@current_admin} active="Team">
      <.link
        navigate={~p"/team"}
        class="mb-4 inline-flex items-center gap-2 text-xs font-semibold text-muted hover:text-ink"
      >
        <.icon name="hero-arrow-left" class="h-4 w-4" /> Team
      </.link>

      <.page_header eyebrow={@admin.public_id} title={display_name(@admin)} description={@admin.email}>
        <:action>
          <.button
            :if={@admin.status == :active}
            variant="secondary"
            phx-click="disable"
            disabled={yourself?(@admin, @current_admin)}
          >
            Disable access
          </.button>
          <.button :if={@admin.status == :disabled} variant="secondary" phx-click="enable">
            Enable access
          </.button>
        </:action>
      </.page_header>

      <div class="grid max-w-4xl items-start gap-4 lg:grid-cols-2">
        <.surface>
          <.list_header title="Role" description="What this account may do in the console." />

          <form phx-change="role" class="px-5 py-5">
            <.input
              type="select"
              name="role"
              value={@admin.role}
              label="Role"
              options={@role_options}
              disabled={yourself?(@admin, @current_admin)}
              help={
                if yourself?(@admin, @current_admin),
                  do: "You cannot change your own role.",
                  else: "Superadmins manage staff; support reads and helps."
              }
            />
          </form>
        </.surface>

        <div class="space-y-4">
          <.surface>
            <.list_header title="Access" />
            <dl>
              <.field label="Status"><.status value={@admin.status} /></.field>
              <.field label="Last signed in">{last_seen(@admin)}</.field>
              <.field label="Added">{Format.datetime(@admin.inserted_at)}</.field>
            </dl>
          </.surface>

          <.surface>
            <.list_header title="Password" description="Issue a new one if they cannot sign in." />
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
        <p class="text-sm text-ink">{@admin.email}</p>

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

  defp apply_change(socket, action, message) do
    case action.(socket.assigns.admin) do
      {:ok, admin} ->
        {:noreply, socket |> assign(admin: admin) |> put_flash(:info, message)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not change that account.")}
    end
  end

  defp yourself?(admin, current_admin), do: admin.id == current_admin.id

  defp display_name(admin) do
    case String.trim(to_string(admin.name)) do
      "" -> admin.email |> String.split("@") |> hd()
      name -> name
    end
  end

  defp last_seen(%{last_login_at: nil}), do: "Never"
  defp last_seen(%{last_login_at: at}), do: Format.datetime(at)

  defp options(values) do
    Enum.map(values, fn value -> {value |> to_string() |> String.capitalize(), value} end)
  end
end
