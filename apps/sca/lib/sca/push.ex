defmodule Sca.Push do
  @moduledoc """
  Telling a phone that something is waiting for it.

  Best effort by design: a device that misses the notification still sees the
  request when it next opens the app, so nothing here can fail an approval. A
  binding without a push token is not an error either.
  """

  require Logger

  alias Sca.Models.Binding
  alias Sca.Models.Request
  alias Sca.Workers.PushWorker

  @doc """
  The Firebase project notifications go to, or `nil` when push is not set up.

  Unconfigured is a supported state, not a broken one: everything else works,
  and devices fall back to seeing requests when they poll.
  """
  @spec project_id() :: String.t() | nil
  def project_id, do: config()[:project_id]

  @doc "Whether push is configured at all."
  @spec configured?() :: boolean()
  def configured?, do: not is_nil(project_id()) and not is_nil(config()[:credentials])

  @doc "The service-account credentials Goth signs with."
  @spec credentials() :: map() | nil
  def credentials, do: config()[:credentials]

  defp config, do: Application.get_env(:sca, __MODULE__, [])

  @doc """
  Queues a notification for a request, inside the caller's transaction.

  Mirrors `Sca.Webhooks.queue/2`: the job commits with the row it announces.
  """
  @spec queue(Request.t(), Binding.t()) :: {:ok, :queued | :no_token} | {:error, term()}
  def queue(%Request{} = request, %Binding{push_token: token} = binding)
      when is_binary(token) and token != "" do
    with {:ok, _job} <-
           Oban.insert(PushWorker.new(%{request_id: request.id, binding_id: binding.id})) do
      {:ok, :queued}
    end
  end

  def queue(%Request{}, %Binding{} = binding) do
    Logger.debug("[push] #{binding.public_id} has no push token; nothing to send")

    {:ok, :no_token}
  end
end
