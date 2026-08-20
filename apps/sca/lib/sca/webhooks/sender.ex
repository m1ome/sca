defmodule Sca.Webhooks.Sender do
  @moduledoc """
  Sending one delivery and writing down what came back.

  Separate from `Sca.Webhooks` on purpose: that module decides *what* a merchant
  should hear about, this one deals with the wire and with a merchant's server
  being slow, broken or gone.
  """

  require Logger

  alias Sca.Models.WebhookDelivery
  alias Sca.Repo
  alias Sca.Repos.WebhookDeliveryRepo
  alias Sca.Telemetry
  alias Sca.Webhooks.Client
  alias Sca.Webhooks.Envelope

  @doc """
  Sends a delivery and records the attempt.

  Returns `:ok` when the merchant accepted it and `{:error, reason}` otherwise,
  so the worker retries; the row is closed as `:failed` once the last attempt is
  spent. A body we cannot even build — a certificate that stopped being usable —
  cancels the job instead of burning attempts on something no retry will fix.
  """
  @spec deliver(WebhookDelivery.t(), pos_integer(), pos_integer()) ::
          :ok | {:error, term()} | {:cancel, term()}
  def deliver(%WebhookDelivery{} = delivery, attempt, max_attempts) do
    delivery = Repo.preload(delivery, :tenant)

    case Envelope.build(delivery, delivery.tenant) do
      {:ok, body, headers} ->
        {result, duration} = post(delivery, body, headers)

        record(delivery, result, attempt, max_attempts, duration)

      {:error, reason} ->
        Logger.error("[webhooks] #{delivery.public_id} cannot be built: #{inspect(reason)}")
        mark_failed(delivery, reason, attempt)

        {:cancel, reason}
    end
  end

  defp post(delivery, body, headers) do
    started = System.monotonic_time(:millisecond)
    result = Client.post(delivery.url, body, headers)

    {result, System.monotonic_time(:millisecond) - started}
  end

  defp record(delivery, result, attempt, max_attempts, duration) do
    {status, response} = classify(result, attempt >= max_attempts)
    verdict = verdict(status, response)

    write(delivery, status, response, attempt, duration)
    log(delivery, status, verdict, attempt, max_attempts, duration)

    verdict
  end

  defp mark_failed(delivery, reason, attempt) do
    write(delivery, :failed, %{error: inspect(reason), response_status: nil}, attempt, 0)
  end

  defp write(delivery, status, response, attempt, duration) do
    now = Timex.now()

    {:ok, _delivery} =
      WebhookDeliveryRepo.record_attempt(
        delivery,
        Map.merge(response, %{
          status: status,
          attempts: attempt,
          duration_ms: duration,
          last_attempt_at: now,
          delivered_at: if(status == :delivered, do: now)
        })
      )

    Telemetry.emit(
      [:webhook, :attempt],
      %{count: 1, duration_ms: duration, attempt: attempt},
      %{event: delivery.event, status: status, tenant_id: delivery.tenant_id}
    )
  end

  defp classify({:ok, %{status: status, body: body}}, _last?) when status in 200..299 do
    {:delivered, %{response_status: status, response_body: body, error: nil}}
  end

  defp classify({:ok, %{status: status, body: body}}, last?) do
    {open_or_closed(last?), %{response_status: status, response_body: body, error: nil}}
  end

  defp classify({:error, reason}, last?) do
    {open_or_closed(last?), %{error: inspect(reason), response_status: nil}}
  end

  defp verdict(:delivered, _response), do: :ok
  defp verdict(_status, %{error: error}) when is_binary(error), do: {:error, error}
  defp verdict(_status, %{response_status: status}), do: {:error, "http #{status}"}

  defp open_or_closed(true), do: :failed
  defp open_or_closed(false), do: :pending

  defp log(delivery, :delivered, _verdict, attempt, _max, duration) do
    Logger.info(
      "[webhooks] delivered #{delivery.public_id} in #{duration}ms (attempt #{attempt})"
    )
  end

  defp log(delivery, :failed, {:error, reason}, attempt, max, _duration) do
    Logger.error("[webhooks] gave up on #{delivery.public_id} after #{attempt}/#{max}: #{reason}")
  end

  defp log(delivery, _status, {:error, reason}, attempt, max, _duration) do
    Logger.warning(
      "[webhooks] #{delivery.public_id} failed on #{attempt}/#{max}, retrying: #{reason}"
    )
  end
end
