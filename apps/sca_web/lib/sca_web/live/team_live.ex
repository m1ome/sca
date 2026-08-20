defmodule ScaWeb.TeamLive do
  @moduledoc """
  Who from the merchant can sign into this console.

  Adding a member produces a password shown exactly once — the same shape as an
  activation code, for the same reason: we keep the hash, not the secret.
  """

  use ScaWeb, :live_view

  alias Sca.Actions
  alias Sca.Models.User
  alias Sca.Repos.UserRepo

  @roles Ecto.Enum.values(User, :role)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Team", role_options: options(@roles))
     |> assign(modal: :closed, form: member_form(), credentials: nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {members, meta} = UserRepo.page_for_tenant(socket.assigns.current_tenant, flop(params))

    {:noreply, socket |> assign(meta: meta) |> stream(:members, members, reset: true)}
  end

  @impl true
  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: ~p"/team?page=#{page}")}
  end

  def handle_event("new", _params, socket) do
    {:noreply, assign(socket, modal: :form, form: member_form(), credentials: nil)}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, modal: :closed, credentials: nil)}
  end

  def handle_event("add", %{"user" => params}, socket) do
    case Actions.Tenant.add_user(socket.assigns.current_tenant, params) do
      {:ok, %{user: user, password: password}} ->
        {:noreply,
         socket
         |> assign(modal: :credentials, credentials: %{user: user, password: password})
         |> stream_insert(:members, user, at: 0)}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :user))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_tenant={@current_tenant}
      active="Team"
    >
      <.page_header
        eyebrow="Console access"
        title="Team"
        description="The people who can raise approvals and manage devices for your merchant."
      >
        <:action>
          <.button phx-click="new">
            <.icon name="hero-plus" class="h-4 w-4" /> Add member
          </.button>
        </:action>
      </.page_header>

      <.surface>
        <.list_header title="Members" description={"#{@meta.total_count} in total"} />

        <.table id="members" rows={@streams.members} stream>
          <:col :let={member} label="Member">
            <p class="truncate font-medium">{display_name(member)}</p>
            <p class="truncate text-xs text-muted">{member.email}</p>
          </:col>
          <:col :let={member} label="Role" width="w-32" hide_below="sm">
            <span class="text-muted">{String.capitalize(to_string(member.role))}</span>
          </:col>
          <:col :let={member} label="State" width="w-32">
            <.status value={member.status} />
          </:col>
          <:col :let={member} label="Added" width="w-44" hide_below="md">
            <span class="text-muted" title={Format.datetime(member.inserted_at)}>
              {Format.relative(member.inserted_at)}
            </span>
          </:col>
          <:action :let={member}>
            <.link
              navigate={~p"/team/#{member.public_id}"}
              class="text-sm font-semibold text-brand hover:text-brand-strong"
            >
              View
            </.link>
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
        id="new-member"
        show
        on_cancel={JS.push("close")}
        title="Add member"
        description="They will get a password to sign in with."
      >
        <.form :let={f} for={@form} id="member-form" phx-submit="add" class="space-y-4">
          <.input
            field={f[:email]}
            type="email"
            label="Email"
            placeholder="name@merchant.com"
            required
          />
          <.input field={f[:name]} label="Name" placeholder="Dana Ops" />
          <.input
            field={f[:role]}
            type="select"
            label="Role"
            options={@role_options}
            help="Owners manage the team; viewers only read."
          />
        </.form>

        <:footer>
          <.button variant="secondary" phx-click="close">Cancel</.button>
          <.button type="submit" form="member-form">Add member</.button>
        </:footer>
      </.modal>

      <.modal
        :if={@modal == :credentials}
        id="member-credentials"
        show
        on_cancel={JS.push("close")}
        title="Password for the new member"
        description="Shown once. We keep the hash, never the password itself."
      >
        <p class="text-sm text-ink">{@credentials.user.email}</p>

        <div class="mt-3 rounded-xl border border-line bg-canvas px-4 py-4 text-center">
          <p id="member-password" class="break-all font-mono text-sm font-semibold text-ink">
            {@credentials.password}
          </p>
        </div>

        <:footer>
          <.button
            variant="secondary"
            phx-click={JS.dispatch("sca:copy", to: "#member-password")}
          >
            Copy password
          </.button>
          <.button phx-click="close">Done</.button>
        </:footer>
      </.modal>
    </Layouts.app>
    """
  end

  defp display_name(member) do
    case String.trim(to_string(member.name)) do
      "" -> member.email |> String.split("@") |> hd()
      name -> name
    end
  end

  defp member_form, do: to_form(%{"email" => "", "name" => "", "role" => "admin"}, as: :user)

  defp options(values) do
    Enum.map(values, fn value -> {value |> to_string() |> String.capitalize(), value} end)
  end

  defp flop(params), do: %{"page" => params["page"] || 1, "page_size" => 20}
end
