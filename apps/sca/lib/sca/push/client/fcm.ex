defmodule Sca.Push.Client.Fcm do
  @moduledoc """
  FCM HTTP v1, authenticated with a Google service account.

  The service-account JWT dance is Goth's — it signs, exchanges and caches the
  access token, which is exactly the kind of thing worth not writing ourselves.

  Unconfigured is a no-op: a developer without Firebase credentials still gets
  a working server, and a missing credential is a configuration problem, not a
  failed approval.
  """

  @behaviour Sca.Push.Client

  require Logger

  @endpoint "https://fcm.googleapis.com/v1/projects"

  @impl true
  def send(message) do
    case Sca.Push.project_id() do
      nil ->
        Logger.debug("[push] FCM is not configured; dropping the notification")
        :ok

      project ->
        deliver(project, message)
    end
  end

  defp deliver(project, message) do
    with {:ok, %{token: token}} <- Goth.fetch(Sca.Goth) do
      "#{@endpoint}/#{project}/messages:send"
      |> Req.post(json: message, auth: {:bearer, token}, retry: false, receive_timeout: 10_000)
      |> handle()
    end
  rescue
    error -> {:error, Exception.message(error)}
  catch
    # Goth may be gone for good (see `Sca.Application`).
    :exit, reason -> {:error, "goth is unavailable: #{inspect(reason)}"}
  end

  defp handle({:ok, %Req.Response{status: status}}) when status in 200..299, do: :ok

  # Uninstalled, restored elsewhere, or expired. No retry fixes that.
  defp handle({:ok, %Req.Response{status: 404}}), do: {:error, :unregistered}

  defp handle({:ok, %Req.Response{status: status, body: body}}) do
    {:error, "fcm #{status}: #{inspect(body)}"}
  end

  defp handle({:error, reason}), do: {:error, reason}
end
