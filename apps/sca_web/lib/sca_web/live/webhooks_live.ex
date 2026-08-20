defmodule ScaWeb.WebhooksLive do
  @moduledoc """
  Every call we made to the merchant's endpoint, and what came back.

  This is the screen someone opens when a decision did not reach their system:
  it answers what we sent, when, how many times we tried, and what their server
  said — including the body of their own error. Test events sent from Settings
  land here too, marked as such.
  """

  use ScaWeb, :live_view

  alias Sca.Models.WebhookDelivery
  alias Sca.Repos.WebhookDeliveryRepo
  alias Sca.Search
  alias Sca.Webhooks

  @statuses Ecto.Enum.values(WebhookDelivery, :status)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Webhooks",
       status_options: options(@statuses),
       event_options: options(Webhooks.events()),
       selected: nil
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = filters(params)

    {deliveries, meta} =
      WebhookDeliveryRepo.page_for_tenant(socket.assigns.current_tenant, flop(filters, params))

    {:noreply,
     socket
     |> assign(filters: filters, meta: meta)
     |> stream(:deliveries, deliveries, reset: true)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply, push_patch(socket, to: ~p"/webhooks?#{query(filters(params), 1)}")}
  end

  def handle_event("page", %{"page" => page}, socket) do
    {:noreply, push_patch(socket, to: ~p"/webhooks?#{query(socket.assigns.filters, page)}")}
  end

  def handle_event("inspect", %{"id" => public_id}, socket) do
    case Sca.Scope.fetch_delivery(socket.assigns.current_scope, public_id) do
      {:ok, delivery} -> {:noreply, assign(socket, selected: delivery)}
      {:error, :not_found} -> {:noreply, put_flash(socket, :error, "That delivery is gone.")}
    end
  end

  def handle_event("close", _params, socket), do: {:noreply, assign(socket, selected: nil)}

  def handle_event("retry", %{"id" => public_id}, socket) do
    case resend(socket.assigns.current_scope, public_id) do
      {:ok, delivery} ->
        {:noreply,
         socket
         |> stream_insert(:deliveries, delivery)
         |> assign(selected: nil)
         |> put_flash(:info, "#{delivery.public_id} is on its way again.")}

      {:error, :already_queued} ->
        {:noreply,
         socket
         |> assign(selected: nil)
         |> put_flash(:info, "That delivery is already waiting to go out.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "That delivery could not be queued.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_tenant={@current_tenant}
      active="Webhooks"
    >
      <.page_header
        eyebrow="Outgoing"
        title="Webhooks"
        description="What we sent to your endpoint, and what it answered."
      />

      <form phx-change="filter" class="mb-4 grid gap-3 sm:grid-cols-3">
        <.input
          type="select"
          name="status"
          value={@filters["status"]}
          label="State"
          prompt="All states"
          options={@status_options}
        />
        <.input
          type="select"
          name="event"
          value={@filters["event"]}
          label="Event"
          prompt="All events"
          options={@event_options}
        />
        <.input
          name="search"
          value={@filters["search"]}
          label="Find"
          placeholder="WHK-88 or a uuid"
          help="An id from a log or from the delivery header."
        />
      </form>

      <.surface>
        <.list_header title="Deliveries" description={"#{@meta.total_count} in total"} />

        <.table id="deliveries" rows={@streams.deliveries} stream>
          <:col :let={delivery} label="Event">
            <p class="truncate font-medium">{delivery.event}</p>
            <p class="truncate text-xs text-muted">
              {delivery.public_id}<span :if={delivery.test}> · test event</span>
            </p>
          </:col>
          <:col :let={delivery} label="Answer" width="w-40" hide_below="sm">
            <span class="text-muted">{response(delivery)}</span>
          </:col>
          <:col :let={delivery} label="Tries" width="w-20" hide_below="md">
            <span class="text-muted">{delivery.attempts}</span>
          </:col>
          <:col :let={delivery} label="State" width="w-32">
            <.status value={delivery.status} />
          </:col>
          <:col :let={delivery} label="Last attempt" width="w-44" hide_below="md">
            <span class="text-muted" title={Format.datetime(moment(delivery))}>
              {Format.relative(moment(delivery))}
            </span>
          </:col>
          <:action :let={delivery}>
            <.button variant="ghost" phx-click="inspect" phx-value-id={delivery.public_id}>
              Open
            </.button>
          </:action>
        </.table>

        <.empty_state
          :if={@meta.total_count == 0}
          title="Nothing delivered yet"
          description="Decisions show up here as soon as your endpoint is set in Settings."
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
        :if={@selected}
        id="delivery"
        show
        on_cancel={JS.push("close")}
        title={@selected.event}
        description={@selected.public_id}
      >
        <dl>
          <.field label="State"><.status value={@selected.status} /></.field>
          <.field :if={@selected.test} label="Kind">
            Test event, sent from Settings against a sample payload
          </.field>
          <.field label="Endpoint">
            <span class="break-all font-mono text-xs">{@selected.url}</span>
          </.field>
          <.field label="Attempts">{@selected.attempts}</.field>
          <.field label="Last attempt">{Format.datetime(@selected.last_attempt_at)}</.field>
          <.field :if={@selected.delivered_at} label="Delivered">
            {Format.datetime(@selected.delivered_at)}
          </.field>
          <.field label="Answer">{response(@selected)}</.field>
          <.field :if={@selected.error} label="Error">
            <span class="break-all text-xs text-rose-600">{@selected.error}</span>
          </.field>
          <.field :if={@selected.response_body not in [nil, ""]} label="Body">
            <pre class="max-h-40 overflow-auto rounded-lg border border-line bg-canvas p-3"><code class="whitespace-pre-wrap break-all font-mono text-xs text-ink">{@selected.response_body}</code></pre>
          </.field>
          <.field label="Payload">
            <pre class="max-h-56 overflow-auto rounded-lg border border-line bg-canvas p-3"><code class="whitespace-pre-wrap break-all font-mono text-xs text-ink">{payload(@selected)}</code></pre>
          </.field>
        </dl>

        <:footer>
          <.button variant="secondary" phx-click="close">Close</.button>
          <.button phx-click="retry" phx-value-id={@selected.public_id}>Send again</.button>
        </:footer>
      </.modal>
    </Layouts.app>
    """
  end

  defp resend(scope, public_id) do
    with {:ok, delivery} <- Sca.Scope.fetch_delivery(scope, public_id),
         {:ok, _queued} <- Webhooks.retry(delivery) do
      WebhookDeliveryRepo.get(delivery.id)
    end
  end

  defp moment(delivery), do: delivery.last_attempt_at || delivery.inserted_at

  defp response(%{response_status: status}) when is_integer(status), do: "HTTP #{status}"
  defp response(%{error: error}) when is_binary(error), do: "No answer"
  defp response(_delivery), do: "Not sent yet"

  defp payload(delivery), do: Jason.encode!(delivery.payload, pretty: true)

  defp options(values) do
    Enum.map(values, fn value ->
      {value |> to_string() |> String.replace(".", " ") |> String.capitalize(), value}
    end)
  end

  # Only the filters that were actually chosen: an empty select is not a filter.
  defp filters(params) do
    params
    |> Map.take(["status", "event", "search"])
    |> Map.reject(fn {_key, value} -> value in [nil, ""] end)
  end

  defp query(filters, page), do: Map.put(filters, "page", page)

  defp flop(filters, params) do
    flop_filters =
      filters
      |> Enum.map(fn
        {"search", term} -> Search.filter(term)
        {field, value} -> %{"field" => field, "op" => "==", "value" => value}
      end)
      |> Enum.reject(&is_nil/1)

    %{"page" => params["page"] || 1, "page_size" => 25, "filters" => flop_filters}
  end
end
