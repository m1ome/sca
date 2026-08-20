defmodule Sca.Webhooks.Client do
  @moduledoc """
  The HTTP call a webhook delivery makes.

  A behaviour rather than a direct call for one reason: tests must not reach the
  network. Swapping the client means writing one module, not touching delivery.
  """

  @callback post(url :: String.t(), body :: String.t(), headers :: [{String.t(), String.t()}]) ::
              {:ok, %{status: integer(), body: String.t()}} | {:error, term()}

  @doc "The configured implementation."
  def impl, do: Application.get_env(:sca, :webhook_client, Sca.Webhooks.Client.Req)

  @doc "Posts through the configured implementation."
  def post(url, body, headers), do: impl().post(url, body, headers)
end
