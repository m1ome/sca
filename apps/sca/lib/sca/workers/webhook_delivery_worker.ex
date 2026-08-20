defmodule Sca.Workers.WebhookDeliveryWorker do
  @moduledoc """
  Delivers one webhook and records what came back.

  Jittered backoff from half a minute to an hour: a merchant restarting should
  not make us give up, one that is gone should not be hammered. Every attempt is
  written to the delivery row, error body included.
  """

  # Unique while in flight, so a double-clicked retry sends one webhook.
  # Finished jobs are excluded: `Sca.Webhooks.retry/1` is a deliberate resend.
  use Oban.Worker,
    queue: :webhooks,
    max_attempts: 8,
    unique: [period: :infinity, fields: [:args, :worker], states: :incomplete]

  alias Sca.Repos.WebhookDeliveryRepo
  alias Sca.Webhooks.Sender

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"delivery_id" => id}, attempt: attempt, max_attempts: max}) do
    case WebhookDeliveryRepo.get(id) do
      # Deleted with its tenant: failing the job would only make noise.
      {:error, :not_found} -> :ok
      {:ok, %{status: :delivered}} -> :ok
      {:ok, delivery} -> Sender.deliver(delivery, attempt, max)
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # Exponential, capped at an hour, with jitter: without the jitter every
    # delivery queued while a merchant was down would retry in the same second.
    backoff = min(:math.pow(2, attempt) * 15, 3600)

    trunc(backoff * (1 + :rand.uniform() * 0.2))
  end
end
