defmodule ScaUi.PublicUrl do
  @moduledoc """
  Where the outside world reaches an endpoint, read from its configuration.

  A console has to tell people where to go — the merchant's sign-in page, the
  API a device binds against — and those are other endpoints with other hosts.
  Reading their config keeps that from becoming a dependency on their code.
  """

  @doc """
  The base URL of an endpoint, without a trailing slash.

  In development the config carries no `:url`, so the listening port is the
  fallback and the result is something like `http://localhost:4001`.
  """
  @spec of(atom(), module()) :: String.t()
  def of(otp_app, endpoint) do
    config = Application.get_env(otp_app, endpoint, [])
    url = Keyword.get(config, :url, [])
    scheme = Keyword.get(url, :scheme, "http")
    host = Keyword.get(url, :host, "localhost")
    port = Keyword.get(url, :port) || config |> Keyword.get(:http, []) |> Keyword.get(:port)

    if is_nil(port) or port in [80, 443] do
      "#{scheme}://#{host}"
    else
      "#{scheme}://#{host}:#{port}"
    end
  end
end
