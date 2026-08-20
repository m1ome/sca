defmodule Sca.Push.Message do
  @moduledoc """
  The FCM HTTP v1 body a device receives.

  Both platforms go through FCM — Android directly, iOS onward through APNs — so
  there is one credential and one code path. What it may say is thin on purpose:
  title and description, never the amount or the payee. A push passes through
  Google and Apple onto a lock screen; the details belong in the app.

  Kept apart from the transport so the shape, which is the contract with the
  client, can be asserted without a network.
  """

  alias Sca.Models.Binding
  alias Sca.Models.Request

  # The Approve / Deny actions the app registers under this name.
  @category "sca_auth_actions"

  @doc "The `message` object for one request on one device."
  @spec build(Request.t(), Binding.t()) :: map()
  def build(%Request{} = request, %Binding{} = binding) do
    %{
      "message" => %{
        "token" => binding.push_token,
        "notification" => %{"title" => request.title, "body" => request.description || ""},
        # The deep link, read as `RemoteMessage.data` on both platforms.
        "data" => %{"c" => binding.id, "a" => request.id, "x" => ""},
        "android" => android(request),
        "apns" => apns(request)
      }
    }
  end

  defp android(request) do
    base = %{"priority" => "high"}

    case ttl_seconds(request) do
      nil -> base
      seconds -> Map.put(base, "ttl", "#{seconds}s")
    end
  end

  defp apns(request) do
    # 10 = deliver now, no power-saving coalescing.
    headers = %{"apns-priority" => "10", "apns-push-type" => "alert"}

    headers =
      if ttl_seconds(request) do
        Map.put(headers, "apns-expiration", to_string(Timex.to_unix(request.expires_at)))
      else
        headers
      end

    %{
      "headers" => headers,
      "payload" => %{"aps" => %{"category" => @category, "sound" => "default"}}
    }
  end

  # A stored push must not land after the request it announces died.
  defp ttl_seconds(%Request{expires_at: nil}), do: nil

  defp ttl_seconds(%Request{expires_at: expires_at}) do
    case Timex.diff(expires_at, Timex.now(), :second) do
      seconds when seconds > 0 -> seconds
      _past -> nil
    end
  end
end
