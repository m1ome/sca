defmodule ScaWeb.ApprovalsLive do
  @moduledoc """
  The approvals a merchant has raised, newest first.

  Rows carry what a human needs — what was asked, of which device, how it ended
  and when — and nothing else. Card parameters and the Approve/Decline decision
  belong to the detail screen: a list is for finding, not for deciding.
  """

  use ScaWeb, :live_view

  alias Sca.Models.Request
  alias Sca.Repos.RequestRepo
  alias Sca.Search

  @statuses Ecto.Enum.values(Request, :status)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Approvals", status_options: status_options())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {requests, meta} = RequestRepo.page_for_tenant(socket.assigns.current_tenant, flop(params))

    {:noreply,
     socket
     |> assign(status: params["status"] || "", search: params["search"] || "", meta: meta)
     |> stream(:requests, preload(requests), reset: true)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply, push_patch(socket, to: ~p"/approvals?#{query(params, 1)}")}
  end

  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: ~p"/approvals?#{query(socket.assigns, page)}")}
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
      <.page_header
        eyebrow="Strong customer authentication"
        title="Approvals"
        description="Everything your merchant has asked a bound device to confirm."
      />

      <form phx-change="filter" class="mb-4 grid gap-3 sm:grid-cols-2 lg:max-w-xl">
        <.input
          type="select"
          name="status"
          value={@status}
          label="State"
          prompt="All states"
          options={@status_options}
        />
        <.input
          name="search"
          value={@search}
          label="Find"
          placeholder="REQ-4711 or a uuid"
          help="An id from a log, a webhook or the API."
        />
      </form>

      <.surface>
        <.list_header
          title="Requests"
          description={"#{@meta.total_count} in total"}
        />

        <.table id="approvals" rows={@streams.requests} stream>
          <:col :let={request} label="ID" width="w-28" hide_below="sm">
            <span class="font-mono text-xs text-muted">{request.public_id}</span>
          </:col>
          <:col :let={request} label="Request">
            <p class="truncate font-medium">{request.title}</p>
            <p class="truncate text-xs text-muted">{summary(request)}</p>
          </:col>
          <:col :let={request} label="Type" width="w-28" hide_below="sm">
            <span class="text-muted">{String.capitalize(to_string(request.type))}</span>
          </:col>
          <:col :let={request} label="State" width="w-32">
            <.status value={request.status} />
          </:col>
          <:col :let={request} label="When" width="w-48" hide_below="md">
            <span class="text-muted" title={Format.datetime(moment(request))}>
              {timestamp(request)}
            </span>
          </:col>
          <:action :let={request}>
            <.row_action navigate={~p"/approvals/#{request.public_id}"} />
          </:action>
        </.table>

        <.empty_state
          :if={@meta.total_count == 0}
          title="No approvals yet"
          description="Requests raised through the API will appear here."
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
    </Layouts.app>
    """
  end

  # Which device was asked — never the signed parameters themselves.
  defp summary(%{binding: binding}) do
    case binding.name |> to_string() |> String.trim() do
      "" -> binding.external_id
      name -> name
    end
  end

  defp moment(%{decided_at: nil} = request), do: request.inserted_at
  defp moment(request), do: request.decided_at

  defp timestamp(%{decided_at: nil} = request),
    do: "Raised #{Format.relative(request.inserted_at)}"

  defp timestamp(request),
    do: "#{String.capitalize(to_string(request.status))} #{Format.relative(request.decided_at)}"

  defp preload(requests), do: Sca.Repo.preload(requests, :binding)

  defp status_options do
    Enum.map(@statuses, fn status -> {status |> to_string() |> String.capitalize(), status} end)
  end

  defp flop(params) do
    %{"page" => params["page"] || 1, "page_size" => 20}
    |> Map.put("filters", filters(params))
  end

  defp filters(params) do
    Enum.reject([status_filter(params["status"]), Search.filter(params["search"])], &is_nil/1)
  end

  defp status_filter(status) when status in [nil, ""], do: nil
  defp status_filter(status), do: %{"field" => "status", "op" => "==", "value" => status}

  defp query(params, page) do
    %{"status" => params["status"], "search" => params["search"], "page" => page}
    |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
  end
end
