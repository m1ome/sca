defmodule ScaWeb.AccountLive do
  @moduledoc """
  Your own account, as opposed to the merchant's settings.

  Changing a password here asks for the current one: a console left open on
  somebody's desk should not be enough to take the account over. That is also
  what separates this from the reset an owner can do on the team screen — there
  the account's owner is absent, here they are the one typing.
  """

  use ScaWeb, :live_view

  alias Sca.Actions
  alias ScaWeb.Auth

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Account", error: nil)}
  end

  @impl true
  def handle_event("change-password", %{"password" => params}, socket) do
    %{"current" => current, "new" => new} = params
    user = socket.assigns.current_user
    tenant = socket.assigns.current_tenant

    with {:ok, _user} <- Auth.authenticate(tenant.public_id, user.email, current),
         {:ok, user} <- Actions.Tenant.change_user_password(user, new) do
      {:noreply,
       socket
       |> assign(current_user: user, error: nil)
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
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_tenant={@current_tenant}
      active="Account"
    >
      <.page_header
        eyebrow="Your account"
        title="Account"
        description="Who you are signed in as, and the password you signed in with."
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
          <.list_header title="Signed in as" />
          <dl>
            <.field label="Email">
              <span class="truncate">{@current_user.email}</span>
            </.field>
            <.field label="Role">{String.capitalize(to_string(@current_user.role))}</.field>
            <.field label="Member">{@current_user.public_id}</.field>
            <.field label="Merchant">
              {@current_tenant.name} · {@current_tenant.public_id}
            </.field>
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
