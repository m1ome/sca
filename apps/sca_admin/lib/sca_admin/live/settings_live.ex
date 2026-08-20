defmodule ScaAdmin.SettingsLive do
  @moduledoc """
  Your own account.

  The admin console has nothing to configure per deployment — a cluster is one
  environment, and merchant settings live with the merchant — so what is left
  here is the password of whoever is signed in.
  """

  use ScaAdmin, :live_view

  alias Sca.Actions
  alias ScaAdmin.Auth

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Settings", error: nil)}
  end

  @impl true
  def handle_event("change-password", %{"password" => params}, socket) do
    %{"current" => current, "new" => new} = params

    with {:ok, _admin} <- Auth.authenticate(socket.assigns.current_admin.email, current),
         {:ok, admin} <- Actions.Admin.change_password(socket.assigns.current_admin, new) do
      {:noreply,
       socket
       |> assign(current_admin: admin, error: nil)
       |> put_flash(:info, "Password changed.")}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, error: password_error(changeset))}

      {:error, _reason} ->
        {:noreply, assign(socket, error: "That is not your current password.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_admin={@current_admin} active="Settings">
      <.page_header
        eyebrow="Internal"
        title="Settings"
        description="Your account on this console."
      />

      <div class="grid max-w-4xl items-start gap-4 lg:grid-cols-2">
        <.surface>
          <.list_header title="Password" description="Change the one you signed in with." />

          <form phx-submit="change-password" class="space-y-4 px-5 py-5">
            <p
              :if={@error}
              class="rounded-lg border border-rose-200 bg-rose-50 px-3 py-2 text-xs leading-5 text-rose-700"
            >
              {@error}
            </p>

            <.input
              type="password"
              name="password[current]"
              value=""
              label="Current password"
              autocomplete="current-password"
              required
            />
            <.input
              type="password"
              name="password[new]"
              value=""
              label="New password"
              help="At least 12 characters."
              autocomplete="new-password"
              required
            />

            <.button type="submit">Change password</.button>
          </form>
        </.surface>

        <.surface>
          <.list_header title="Account" />
          <dl>
            <.field label="Email">
              <span class="truncate">{@current_admin.email}</span>
            </.field>
            <.field label="Role">{String.capitalize(to_string(@current_admin.role))}</.field>
            <.field label="Account">{@current_admin.public_id}</.field>
            <.field label="Last signed in">{Format.datetime(@current_admin.last_login_at)}</.field>
          </dl>
        </.surface>
      </div>
    </Layouts.app>
    """
  end

  defp password_error(changeset) do
    changeset
    |> Sca.Errors.to_map()
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end
end
