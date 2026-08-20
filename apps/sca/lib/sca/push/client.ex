defmodule Sca.Push.Client do
  @moduledoc """
  The call that hands a message to FCM.

  A behaviour for the same reason the webhook client is one: tests must not
  reach Google, and the transport is replaceable without touching what we send.
  """

  @callback send(message :: map()) :: :ok | {:error, term()}

  @doc "The configured implementation."
  def impl, do: Application.get_env(:sca, :push_client, Sca.Push.Client.Fcm)

  @doc "Sends through the configured implementation."
  def send(message), do: impl().send(message)
end
