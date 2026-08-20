defmodule Sca.Workers.PushWorker do
  @moduledoc """
  Delivers one notification.

  Fewer attempts and a shorter ladder than a webhook: a push announces a
  request that expires in minutes, so retrying for an hour would wake somebody
  about a decision they can no longer make. Once the request is answered or
  expired there is nothing to announce, and the job says so instead of trying.
  """

  use Oban.Worker,
    queue: :push,
    max_attempts: 3,
    unique: [period: :infinity, fields: [:args, :worker], states: :incomplete]

  import Sca.Actions.Helpers

  require Logger

  alias Sca.Models.Request
  alias Sca.Push.Client
  alias Sca.Push.Message
  alias Sca.Repos.BindingRepo
  alias Sca.Repos.RequestRepo
  alias Sca.Telemetry

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"request_id" => request_id, "binding_id" => binding_id}}) do
    with {:ok, request} <- RequestRepo.get(request_id),
         {:ok, binding} <- BindingRepo.get(binding_id),
         :ok <- still_worth_sending(request, binding) do
      request
      |> Message.build(binding)
      |> Client.send()
      |> record(request, binding)
    else
      {:error, :not_found} -> :ok
      {:error, :stale} -> :ok
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}), do: attempt * 10

  defp still_worth_sending(request, binding) do
    cond do
      not Request.pending?(request) -> {:error, :stale}
      binding.status != :active -> {:error, :stale}
      binding.push_token in [nil, ""] -> {:error, :stale}
      true -> :ok
    end
  end

  # Otherwise every later request queues three more jobs against a dead device.
  defp record({:error, :unregistered}, _request, binding) do
    Logger.info("[push] #{binding.public_id} is unregistered, dropping its token")

    case BindingRepo.update(binding, %{push_token: nil}) do
      {:ok, _binding} ->
        :ok

      {:error, error} ->
        Logger.error("[push] cannot drop the token of #{binding.public_id}: #{reason(error)}")

        :ok
    end
  end

  defp record(:ok, request, binding) do
    Logger.info("[push] sent #{request.public_id} to #{binding.public_id}")

    Telemetry.emit([:push, :sent], %{count: 1}, %{
      platform: binding.push_platform,
      tenant_id: binding.tenant_id
    })

    :ok
  end

  defp record({:error, reason}, request, binding) do
    Logger.warning(
      "[push] #{request.public_id} to #{binding.public_id} failed: #{inspect(reason)}"
    )

    Telemetry.emit([:push, :failed], %{count: 1}, %{
      platform: binding.push_platform,
      tenant_id: binding.tenant_id
    })

    {:error, reason}
  end
end
