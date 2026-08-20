defmodule ScaWeb.SettingsLive do
  @moduledoc """
  Where a merchant tells us how to reach them and how to prove it was us.

  Two things live here per the playbook — the webhook and the signing key —
  plus the deadline every approval inherits, because it is the one setting that
  changes what the phone sees. Recent deliveries sit underneath: the answer to
  "did you actually call us" belongs next to the URL it was called on.

  The test event is here for the same reason. Someone wiring a receiver up needs
  to know their endpoint answers, their signature check passes and their parser
  survives the payload — before a real customer waits on it.
  """

  use ScaWeb, :live_view

  alias Sca.Actions
  alias Sca.Repos.ApiTokenRepo
  alias Sca.Repos.WebhookDeliveryRepo
  alias Sca.Scope
  alias Sca.Webhooks

  @recent_deliveries 10
  @default_test_event "request.confirmed"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Settings", revealed: false, confirming_rotation: false)
     |> assign(issued: nil, revoking: nil)
     |> assign(
       testing: false,
       sending_test: false,
       test_event: @default_test_event,
       test_event_options: event_options(),
       test_result: nil
     )
     |> assign_settings(socket.assigns.current_tenant)}
  end

  @impl true
  def handle_event("save", %{"settings" => params}, socket) do
    case Actions.Tenant.update_settings(socket.assigns.current_tenant, params) do
      {:ok, tenant} ->
        {:noreply,
         socket
         |> assign(current_tenant: tenant)
         |> assign_settings(tenant)
         |> put_flash(:info, "Settings saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :settings))}
    end
  end

  def handle_event("issue-key", _params, socket) do
    case Actions.ApiToken.issue(socket.assigns.current_tenant, %{name: "Console"}) do
      {:ok, %{token: token}} ->
        {:noreply,
         socket
         |> assign(issued: token)
         |> assign_settings(socket.assigns.current_tenant)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not issue a key.")}
    end
  end

  def handle_event("close-key", _params, socket), do: {:noreply, assign(socket, issued: nil)}

  def handle_event("confirm-revoke-key", %{"id" => id}, socket) do
    {:noreply, assign(socket, revoking: id)}
  end

  def handle_event("cancel-revoke-key", _params, socket),
    do: {:noreply, assign(socket, revoking: nil)}

  def handle_event("revoke-key", %{"id" => id}, socket) do
    with {:ok, api_token} <- Scope.fetch_api_token(socket.assigns.current_scope, id),
         {:ok, _revoked} <- Actions.ApiToken.revoke(api_token) do
      {:noreply,
       socket
       |> assign(revoking: nil)
       |> put_flash(:info, "Key revoked. Requests presenting it stop working now.")
       |> assign_settings(socket.assigns.current_tenant)}
    else
      _error ->
        {:noreply,
         socket |> assign(revoking: nil) |> put_flash(:error, "Could not revoke that key.")}
    end
  end

  def handle_event("open-test", _params, socket) do
    {:noreply, assign(socket, testing: true, test_result: nil)}
  end

  def handle_event("close-test", _params, socket) do
    {:noreply, assign(socket, testing: false, test_result: nil)}
  end

  def handle_event("choose-test-event", %{"event" => event}, socket) do
    {:noreply, assign(socket, test_event: event, test_result: nil)}
  end

  def handle_event("send-test", _params, socket) do
    tenant = socket.assigns.current_tenant
    event = socket.assigns.test_event

    {:noreply,
     socket
     |> assign(sending_test: true, test_result: nil)
     |> start_async(:test_webhook, fn -> Webhooks.send_test(tenant, event) end)}
  end

  def handle_event("reveal", _params, socket), do: {:noreply, assign(socket, revealed: true)}
  def handle_event("hide", _params, socket), do: {:noreply, assign(socket, revealed: false)}

  def handle_event("confirm-rotation", _params, socket) do
    {:noreply, assign(socket, confirming_rotation: true)}
  end

  def handle_event("cancel-rotation", _params, socket) do
    {:noreply, assign(socket, confirming_rotation: false)}
  end

  def handle_event("rotate", _params, socket) do
    case Actions.Tenant.rotate_webhook_secret(socket.assigns.current_tenant) do
      {:ok, tenant} ->
        {:noreply,
         socket
         |> assign(current_tenant: tenant, confirming_rotation: false, revealed: true)
         |> assign_settings(tenant)
         |> put_flash(:info, "Signing key rotated. Update your receiver.")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(confirming_rotation: false)
         |> put_flash(:error, "Could not rotate the signing key.")}
    end
  end

  @impl true
  def handle_async(:test_webhook, {:ok, {:ok, delivery}}, socket) do
    {:noreply,
     socket
     |> assign(sending_test: false, test_result: delivery)
     |> assign_settings(socket.assigns.current_tenant)}
  end

  def handle_async(:test_webhook, {:ok, {:error, :no_endpoint}}, socket) do
    {:noreply,
     socket
     |> assign(sending_test: false)
     |> put_flash(:error, "Save an endpoint URL first, then send the test.")}
  end

  def handle_async(:test_webhook, _result, socket) do
    {:noreply,
     socket
     |> assign(sending_test: false)
     |> put_flash(:error, "The test event could not be sent.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_tenant={@current_tenant}
      active="Settings"
    >
      <.page_header
        eyebrow="Merchant"
        title="Settings"
        description="How we reach you when a user decides, and how you know it was us."
      />

      <div class="grid items-start gap-4 lg:grid-cols-[minmax(0,1fr)_320px]">
        <div class="space-y-4">
          <.form :let={f} for={@form} id="settings-form" phx-submit="save">
            <.surface>
              <.list_header
                title="Webhook"
                description="Where decisions are delivered, and how they are protected."
              >
                <:action>
                  <.button variant="secondary" phx-click="open-test">Send test event</.button>
                </:action>
              </.list_header>

              <div class="space-y-4 px-5 py-5">
                <.input
                  field={f[:webhook_url]}
                  label="Endpoint URL"
                  placeholder="https://merchant.example.com/hooks/sca"
                  help="We POST here on every decision, with retries for a day."
                />

                <.input
                  field={f[:webhook_certificate]}
                  type="textarea"
                  label="Encryption certificate"
                  placeholder="-----BEGIN CERTIFICATE-----"
                  help="RSA public key or certificate. With one, the payload arrives as a JWE only you can read."
                />

                <.input
                  field={f[:default_request_timeout_seconds]}
                  type="number"
                  label="Approval timeout (seconds)"
                  help="How long a user has to answer, between 30 and 3600."
                />
              </div>

              <div class="flex justify-end border-t border-line px-5 py-4">
                <.button type="submit">Save settings</.button>
              </div>
            </.surface>
          </.form>

          <.surface>
            <.list_header
              title="API keys"
              description="What your server presents to the merchant API."
            >
              <:action>
                <.button variant="secondary" phx-click="issue-key">Issue key</.button>
              </:action>
            </.list_header>

            <.table id="api-keys" rows={@api_tokens}>
              <:col :let={key} label="ID" width="w-28" hide_below="sm">
                <span class="font-mono text-xs text-muted">{key.public_id}</span>
              </:col>
              <:col :let={key} label="Key">
                <p class="truncate font-mono text-xs">{key.preview}</p>
                <p class="truncate text-xs text-muted">{key_usage(key)}</p>
              </:col>
              <:col :let={key} label="State" width="w-32">
                <.status value={if key.revoked_at, do: "revoked", else: "active"} />
              </:col>
              <:action :let={key}>
                <.button
                  :if={is_nil(key.revoked_at)}
                  variant="danger"
                  size="small"
                  phx-click="confirm-revoke-key"
                  phx-value-id={key.public_id}
                >
                  Revoke
                </.button>
              </:action>
            </.table>

            <.empty_state
              :if={@api_tokens == []}
              title="No keys yet"
              description="Issue one to call the merchant API from your server."
            />
          </.surface>

          <.surface>
            <.list_header
              title="Recent deliveries"
              description="The last calls we made to your endpoint."
            >
              <:action>
                <.link
                  navigate={~p"/webhooks"}
                  class="text-sm font-semibold text-brand hover:text-brand-strong"
                >
                  See all
                </.link>
              </:action>
            </.list_header>

            <.table id="deliveries" rows={@deliveries}>
              <:col :let={delivery} label="ID" width="w-28" hide_below="sm">
                <span class="font-mono text-xs text-muted">{delivery.public_id}</span>
              </:col>
              <:col :let={delivery} label="Event">
                <p class="truncate font-medium">{delivery.event}</p>
                <p class="truncate text-xs text-muted">{response(delivery)}</p>
              </:col>
              <:col :let={delivery} label="State" width="w-32">
                <.status value={delivery.status} />
              </:col>
              <:col :let={delivery} label="Attempted" width="w-44" align="right" hide_below="sm">
                <span
                  class="text-muted"
                  title={Format.datetime(delivery.last_attempt_at || delivery.inserted_at)}
                >
                  {Format.relative(delivery.last_attempt_at || delivery.inserted_at)}
                </span>
              </:col>
            </.table>

            <.empty_state
              :if={@deliveries == []}
              title="Nothing delivered yet"
              description="Decisions will show up here as soon as your endpoint is set."
            />
          </.surface>
        </div>

        <.surface>
          <.list_header
            title="Signing key"
            description="Check the X-SCA-Signature header against this."
          />

          <div class="space-y-3 px-5 py-5">
            <div :if={@revealed} class="rounded-lg border border-line bg-canvas px-3 py-3">
              <.copy_value
                id="signing-key"
                value={@current_tenant.settings.webhook_secret}
                title="Copy signing key"
                class="font-mono text-xs text-ink"
              />
            </div>

            <p
              :if={!@revealed}
              class="rounded-lg border border-line bg-canvas px-3 py-3 font-mono text-xs text-muted"
            >
              ••••••••••••••••••••••••
            </p>

            <div class="flex gap-2">
              <.button :if={!@revealed} variant="secondary" phx-click="reveal" class="flex-1">
                Reveal
              </.button>
              <.button :if={@revealed} variant="secondary" phx-click="hide" class="flex-1">
                Hide
              </.button>
            </div>

            <.button variant="danger" phx-click="confirm-rotation" class="w-full">
              Rotate key
            </.button>
          </div>
        </.surface>
      </div>

      <.modal
        :if={@issued}
        id="issued-key"
        show
        on_cancel={JS.push("close-key")}
        title="Your new API key"
        description="Shown once. We keep a digest, never the key itself."
      >
        <div class="rounded-xl border border-line bg-canvas px-4 py-4">
          <.copy_value
            id="issued-key-value"
            value={@issued}
            title="Copy API key"
            class="font-mono text-xs font-semibold text-ink"
          />
        </div>

        <p class="mt-3 text-xs text-muted">
          Send it as <span class="font-mono">Authorization: Bearer …</span>
          to <span class="font-mono">/api/merchant/v1</span>.
        </p>

        <:footer>
          <.button phx-click="close-key">Done</.button>
        </:footer>
      </.modal>

      <.modal
        :if={@revoking}
        id="revoke-key"
        show
        on_cancel={JS.push("cancel-revoke-key")}
        title="Revoke this key?"
        description="Anything still using it stops working immediately."
      >
        <p class="text-sm leading-6 text-muted">
          Issue a new key and move your traffic to it first if you need to rotate
          without downtime — several keys may be active at once.
        </p>

        <:footer>
          <.button variant="secondary" phx-click="cancel-revoke-key">Keep key</.button>
          <.button variant="danger" phx-click="revoke-key" phx-value-id={@revoking}>
            Revoke key
          </.button>
        </:footer>
      </.modal>

      <.modal
        :if={@confirming_rotation}
        id="rotate-key"
        show
        on_cancel={JS.push("cancel-rotation")}
        title="Rotate the signing key?"
        description="Everything sent after this is signed with the new one."
      >
        <p class="text-sm leading-6 text-muted">
          Calls already queued are signed when they go out, so retries of older deliveries
          will carry the new key too. Update your receiver first, or it will start
          rejecting signatures.
        </p>

        <:footer>
          <.button variant="secondary" phx-click="cancel-rotation">Keep current key</.button>
          <.button variant="danger" phx-click="rotate">Rotate key</.button>
        </:footer>
      </.modal>
      <.modal
        :if={@testing}
        id="test-webhook"
        show
        on_cancel={JS.push("close-test")}
        title="Send a test event"
        description="A made-up event, delivered exactly like a real one."
      >
        <form phx-change="choose-test-event">
          <.input
            type="select"
            name="event"
            value={@test_event}
            label="Event"
            options={@test_event_options}
            help="Same envelope, same signature, same encryption — with a sample payload."
          />
        </form>

        <p class="mt-3 text-xs text-muted">
          It goes to
          <span class="font-mono break-all">
            {@current_tenant.settings.webhook_url || "no endpoint yet"}
          </span>
          once, with no retries, and carries <span class="font-mono">"test": true</span>
          so your receiver can take it apart without acting on it.
        </p>

        <div
          :if={@test_result}
          class="mt-4 rounded-xl border border-line bg-canvas px-4 py-3"
        >
          <dl>
            <.field label="Result"><.status value={@test_result.status} /></.field>
            <.field label="Answer">{response(@test_result)}</.field>
            <.field :if={@test_result.duration_ms} label="Took">
              {@test_result.duration_ms} ms
            </.field>
            <.field :if={@test_result.error} label="Error">
              <span class="break-all text-xs text-rose-600">{@test_result.error}</span>
            </.field>
            <.field :if={@test_result.response_body not in [nil, ""]} label="Body">
              <span class="break-all font-mono text-xs">{@test_result.response_body}</span>
            </.field>
            <.field label="Delivery">
              <.link
                navigate={~p"/webhooks"}
                class="font-mono text-xs text-brand hover:text-brand-strong"
              >
                {@test_result.public_id}
              </.link>
            </.field>
          </dl>
        </div>

        <:footer>
          <.button variant="secondary" phx-click="close-test">Close</.button>
          <.button phx-click="send-test" disabled={@sending_test}>
            {if @sending_test, do: "Sending…", else: "Send test event"}
          </.button>
        </:footer>
      </.modal>
    </Layouts.app>
    """
  end

  defp event_options do
    Enum.map(Webhooks.events(), fn event -> {event, event} end)
  end

  defp assign_settings(socket, tenant) do
    settings = tenant.settings

    assign(socket,
      form:
        to_form(
          %{
            "webhook_url" => settings.webhook_url,
            "webhook_certificate" => settings.webhook_certificate,
            "default_request_timeout_seconds" => settings.default_request_timeout_seconds
          },
          as: :settings
        ),
      deliveries: WebhookDeliveryRepo.list_by_tenant(tenant, limit: @recent_deliveries),
      api_tokens: ApiTokenRepo.list_by_tenant(tenant)
    )
  end

  defp key_usage(%{revoked_at: revoked}) when not is_nil(revoked),
    do: "Revoked #{Format.relative(revoked)}"

  defp key_usage(%{last_used_at: nil}), do: "Never used"
  defp key_usage(%{last_used_at: at}), do: "Last used #{Format.relative(at)}"

  defp response(%{response_status: status}) when is_integer(status), do: "HTTP #{status}"
  defp response(%{error: error}) when is_binary(error), do: error
  defp response(_delivery), do: "Not sent yet"
end
