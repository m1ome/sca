defmodule ScaApi.DeviceAuth do
  @moduledoc """
  Resolves a device's bearer token to its binding.

  Two answers the mobile client depends on telling apart:

    * **403** — this binding is finished. Stop, forget it, bind again.
    * **401** — the token ran out. Renew it and retry.

  `renewal: true` accepts a token that expired within
  `Sca.Models.Binding.renewal_grace/0`, and only the two refresh endpoints use
  it: renewing costs a hardware-key signature, so an expired bearer alone still
  buys nothing.
  """

  import Plug.Conn

  alias Sca.Models.Binding
  alias Sca.Repos.BindingRepo

  def init(opts), do: opts

  def call(conn, opts) do
    grace =
      if Keyword.get(opts, :renewal, false), do: Binding.seconds(Binding.renewal_grace()), else: 0

    with {:ok, presented} <- bearer(conn),
         {:ok, binding} <- BindingRepo.get_by_access_token(presented),
         :active <- binding.status,
         false <- expired?(binding.access_token_expires_at, grace) do
      assign(conn, :current_binding, binding)
    else
      :pending -> halt_with(conn, 403, "revoked", "This binding is no longer active.")
      :revoked -> halt_with(conn, 403, "revoked", "This binding is no longer active.")
      true -> halt_with(conn, 401, "token_expired", "This access token has expired.")
      _unauthorised -> halt_with(conn, 401, "unauthorized", "Present a valid access token.")
    end
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _rest] -> {:ok, String.trim(token)}
      ["bearer " <> token | _rest] -> {:ok, String.trim(token)}
      _missing -> :error
    end
  end

  defp expired?(nil, _grace), do: true

  defp expired?(deadline, grace) do
    Timex.before?(Timex.shift(deadline, seconds: grace), Timex.now())
  end

  defp halt_with(conn, status, code, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: %{code: code, message: message}}))
    |> halt()
  end
end
