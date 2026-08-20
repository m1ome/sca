defmodule ScaAdmin.TeamLive do
  @moduledoc """
  Who from our side can open this console.

  Adding somebody produces a password shown exactly once — the same pattern as
  everywhere else in the product, for the same reason.
  """

  use ScaAdmin, :live_view

  alias Sca.Actions
  alias Sca.Models.Admin
  alias Sca.Repos.AdminRepo

  @roles Ecto.Enum.values(Admin, :role)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Team", role_options: options(@roles))
     |> assign(modal: :closed, form: admin_form(), credentials: nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {admins, meta} = AdminRepo.page(%{"page" => params["page"] || 1, "page_size" => 20})

    {:noreply, socket |> assign(meta: meta) |> stream(:admins, admins, reset: true)}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: ~p"/team?page=#{page}")}
  end

  def handle_event("new", _params, socket) do
    {:noreply, assign(socket, modal: :form, form: admin_form(), credentials: nil)}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, modal: :closed, credentials: nil)}
  end

  def handle_event("add", %{"admin" => params}, socket) do
    case Actions.Admin.create(params) do
      {:ok, %{admin: admin, password: password}} ->
        {:noreply,
         socket
         |> assign(modal: :credentials, credentials: %{admin: admin, password: password})
         |> stream_insert(:admins, admin, at: 0)}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :admin))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_admin={@current_admin} active="Team">
      <.page_header
        eyebrow="Internal"
        title="Team"
        description="Staff accounts with access to every merchant on this cluster."
      >
        <:action>
          <.button phx-click="new">
            <.icon name="hero-plus" class="h-4 w-4" /> Add staff
          </.button>
        </:action>
      </.page_header>

      <.surface>
        <.list_header title="Staff" description={"#{@meta.total_count} in total"} />

        <.table id="admins" rows={@streams.admins} stream>
          <:col :let={admin} label="ID" width="w-28" hide_below="sm">
            <span class="font-mono text-xs text-muted">{admin.public_id}</span>
          </:col>
          <:col :let={admin} label="Person">
            <p class="truncate font-medium">{display_name(admin)}</p>
            <p class="truncate text-xs text-muted">{admin.email}</p>
          </:col>
          <:col :let={admin} label="Role" width="w-32" hide_below="sm">
            <span class="text-muted">{String.capitalize(to_string(admin.role))}</span>
          </:col>
          <:col :let={admin} label="State" width="w-32">
            <.status value={admin.status} />
          </:col>
          <:col :let={admin} label="Last seen" width="w-44" hide_below="md">
            <span class="text-muted" title={Format.datetime(admin.last_login_at)}>
              {last_seen(admin)}
            </span>
          </:col>
          <:action :let={admin}>
            <.row_action navigate={~p"/team/#{admin.public_id}"} />
          </:action>
        </.table>
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
        id="new-admin"
        show
        on_cancel={JS.push("close")}
        title="Add staff"
        description="They will get a password to sign in with."
      >
        <.form :let={f} for={@form} id="admin-form" phx-submit="add" class="space-y-4">
          <.input field={f[:email]} type="email" label="Email" placeholder="name@enum8.com" required />
          <.input field={f[:name]} label="Name" placeholder="Sam Support" />
          <.input
            field={f[:role]}
            type="select"
            label="Role"
            options={@role_options}
            help="Superadmins manage staff; support reads and helps."
          />
        </.form>

        <:footer>
          <.button variant="secondary" phx-click="close">Cancel</.button>
          <.button type="submit" form="admin-form">Add staff</.button>
        </:footer>
      </.modal>

      <.modal
        :if={@modal == :credentials}
        id="admin-credentials"
        show
        on_cancel={JS.push("close")}
        title="Password for the new account"
        description="Shown once. We keep the hash, never the password itself."
      >
        <p class="text-sm text-ink">{@credentials.admin.email}</p>

        <div class="mt-3 rounded-xl border border-line bg-canvas px-4 py-4">
          <.copy_value
            id="admin-password"
            value={@credentials.password}
            title="Copy password"
            class="font-mono text-sm font-semibold text-ink"
          />
        </div>

        <:footer>
          <.button phx-click="close">Done</.button>
        </:footer>
      </.modal>
    </Layouts.app>
    """
  end

  defp display_name(admin) do
    case String.trim(to_string(admin.name)) do
      "" -> admin.email |> String.split("@") |> hd()
      name -> name
    end
  end

  defp last_seen(%{last_login_at: nil}), do: "Never signed in"
  defp last_seen(%{last_login_at: at}), do: Format.relative(at)

  defp admin_form, do: to_form(%{"email" => "", "name" => "", "role" => "support"}, as: :admin)

  defp options(values) do
    Enum.map(values, fn value -> {value |> to_string() |> String.capitalize(), value} end)
  end
end
