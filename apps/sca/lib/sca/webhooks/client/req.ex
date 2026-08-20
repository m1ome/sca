defmodule Sca.Webhooks.Client.Req do
  @moduledoc """
  Webhook client on Req.

  Redirects are not followed and retries are Oban's: a webhook URL that
  redirects is a misconfiguration on the merchant's side, and following it would
  send a signed payload somewhere the tenant never named. Retrying inside the
  HTTP call would also hide the attempt from the delivery row, which is the
  thing support looks at.
  """

  @behaviour Sca.Webhooks.Client

  @connect_timeout_ms 5_000
  @receive_timeout_ms 10_000

  @impl true
  def post(url, body, headers) do
    case Req.post(url, request_options(body, headers)) do
      {:ok, %Req.Response{status: status, body: response_body}} ->
        {:ok, %{status: status, body: to_string(response_body)}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp request_options(body, headers) do
    [
      body: body,
      headers: headers,
      # The merchant's answer is for the audit trail, not for us to interpret.
      decode_body: false,
      redirect: false,
      retry: false,
      receive_timeout: @receive_timeout_ms,
      connect_options: [timeout: @connect_timeout_ms]
    ]
  end
end
