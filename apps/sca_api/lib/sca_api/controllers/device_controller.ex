defmodule ScaApi.DeviceController do
  @moduledoc """
  The device-facing API, `/api/sca/v1`.

  The shape is fixed by the mobile client: it is already in people's pockets, so
  this is a contract, not a design space. Two answers it depends on: 403 means
  the binding is finished, 401 means the token ran out and renewing is worth
  trying.
  """

  use ScaApi, :controller

  alias Sca.Actions
  alias Sca.Repos.BindingRepo
  alias Sca.Repos.RequestRepo
  alias ScaApi.JSON
  alias ScaApi.TenantPath

  # A session that belongs to another merchant than the path names is not this
  # merchant's device. Runs after the pipeline, so the binding is resolved.
  plug :ensure_path_tenant when action not in [:bind]

  @doc "Binds a device with the code from the QR."
  def bind(conn, params) do
    with {:ok, connect_token} <- fetch(params, "connect_token"),
         %Plug.Conn{halted: false} <- ensure_enrollment_tenant(conn, connect_token),
         {:ok, session} <- Actions.Binding.bind(connect_token, device_attrs(params)) do
      conn |> put_status(:created) |> json(JSON.session(session))
    else
      {:error, :not_found} ->
        error(conn, :not_found, "unknown_code", "No enrollment matches that code.")

      {:error, reason} when reason in [:enrollment_used, :enrollment_expired] ->
        error(conn, :conflict, to_string(reason), "That code cannot be used any more.")

      {:error, %Ecto.Changeset{} = changeset} ->
        invalid(conn, changeset)

      {:error, :missing_field} ->
        error(conn, :bad_request, "invalid_request", "connect_token and public_key are required.")

      %Plug.Conn{halted: true} = halted ->
        halted
    end
  end

  defp ensure_path_tenant(conn, _opts) do
    TenantPath.ensure_owner(conn, conn.assigns[:current_binding])
  end

  # The enrollment is looked up before it is spent: a code offered under the
  # wrong merchant must not bind a device and then be refused.
  defp ensure_enrollment_tenant(%{assigns: %{path_tenant: _tenant}} = conn, connect_token) do
    case BindingRepo.get_by_enroll_token(connect_token) do
      {:ok, binding} -> TenantPath.ensure_owner(conn, binding)
      {:error, :not_found} -> conn
    end
  end

  defp ensure_enrollment_tenant(conn, _connect_token), do: conn

  @doc "The requests this device still has to answer."
  def pending(conn, _params) do
    conn.assigns.current_binding
    |> RequestRepo.list_pending()
    |> Enum.map(&JSON.authorization/1)
    |> then(&json(conn, &1))
  end

  @doc "One request, by id — what a push deep-link opens."
  def show(conn, %{"id" => id}) do
    binding = conn.assigns.current_binding

    case RequestRepo.get(id) do
      {:ok, %{binding_id: binding_id} = request} when binding_id == binding.id ->
        json(conn, JSON.authorization(request))

      # Somebody else's request is not found, not forbidden: an id that answers
      # differently for a stranger is an id worth guessing.
      _other ->
        error(conn, :not_found, "not_found", "No such authorization.")
    end
  end

  @doc "Confirms or denies a request, with the signature the device made."
  def decide(conn, %{"id" => id} = params) do
    binding = conn.assigns.current_binding

    with {:ok, decision} <- fetch(params, "decision"),
         {:ok, signature} <- fetch(params, "signature"),
         {:ok, %{binding_id: binding_id} = request} when binding_id == binding.id <-
           RequestRepo.get(id),
         {:ok, decided} <- Actions.Request.decide(request, binding, decision, signature) do
      json(conn, JSON.authorization(decided))
    else
      {:error, :already_decided} ->
        error(conn, :conflict, "already_decided", "This authorization was already answered.")

      {:error, :expired} ->
        error(conn, :gone, "expired", "This authorization has expired.")

      {:error, reason} when reason in [:invalid_signature, :invalid_decision] ->
        error(conn, :bad_request, to_string(reason), "That decision could not be accepted.")

      {:error, :missing_field} ->
        error(conn, :bad_request, "invalid_request", "decision and signature are required.")

      _not_ours ->
        error(conn, :not_found, "not_found", "No such authorization.")
    end
  end

  @doc "Issues the challenge a device signs to renew its session."
  def refresh_challenge(conn, _params) do
    case Actions.Binding.issue_refresh_challenge(conn.assigns.current_binding) do
      {:ok, %{nonce: nonce}} ->
        json(conn, %{nonce: nonce})

      {:error, :revoked} ->
        error(conn, :forbidden, "revoked", "This binding is no longer active.")

      {:error, _reason} ->
        error(conn, :bad_request, "unavailable", "Could not issue a challenge.")
    end
  end

  @doc "Renews the session, given a signature over that challenge."
  def refresh(conn, params) do
    with {:ok, signature} <- fetch(params, "signature"),
         {:ok, binding} <-
           Actions.Binding.refresh_session(conn.assigns.current_binding, signature) do
      json(conn, %{
        access_token_expires_at: Timex.format!(binding.access_token_expires_at, "{RFC3339z}")
      })
    else
      {:error, :revoked} ->
        error(conn, :forbidden, "revoked", "This binding is no longer active.")

      {:error, reason} when reason in [:invalid_proof, :no_challenge, :missing_field] ->
        error(conn, :bad_request, "invalid_proof", "That proof of possession was not accepted.")
    end
  end

  @doc "Re-registers the push token after the OS rotated it."
  def push_token(conn, params) do
    with {:ok, token} <- fetch(params, "push_token"),
         {:ok, _binding} <-
           Actions.Binding.update_push_token(
             conn.assigns.current_binding,
             token,
             platform(params["push_platform"])
           ) do
      json(conn, %{status: "updated"})
    else
      {:error, :revoked} ->
        error(conn, :forbidden, "revoked", "This binding is no longer active.")

      {:error, %Ecto.Changeset{} = changeset} ->
        invalid(conn, changeset)

      {:error, :missing_field} ->
        error(conn, :bad_request, "invalid_request", "push_token is required.")
    end
  end

  @doc """
  Unbinds this device.

  The binding is named in the path even though the bearer already says who is
  asking: a client that has paired the wrong token with the wrong stored id
  would otherwise revoke whichever the token points at, silently and from the
  user's point of view wrongly.
  """
  def revoke(conn, %{"id" => id}) do
    binding = conn.assigns.current_binding

    if id == binding.id do
      case Actions.Binding.revoke(binding, :device) do
        {:ok, _binding} -> json(conn, %{status: "revoked"})
        {:error, _reason} -> error(conn, :bad_request, "unavailable", "Could not revoke.")
      end
    else
      error(conn, :not_found, "not_found", "No such connection.")
    end
  end

  defp device_attrs(params) do
    %{
      "public_key" => params["public_key"],
      "algorithm" => params["algorithm"] || Sca.Crypto.algorithm_ecdsa_p256(),
      "name" => params["name"] || "",
      "device_info" => params["device_info"] || %{},
      "push_token" => params["push_token"],
      "push_platform" => platform(params["push_platform"])
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  # The client sends an OS name; anything but these two arrives without one.
  defp platform(value) when value in ["ios", "iOS", "IOS"], do: :ios
  defp platform(value) when value in ["android", "Android", "ANDROID"], do: :android
  defp platform(_value), do: nil

  defp fetch(params, key) do
    case params[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _missing -> {:error, :missing_field}
    end
  end

  defp invalid(conn, changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(
      JSON.error("invalid_request", "Some fields were rejected.", Sca.Errors.to_map(changeset))
    )
  end

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(JSON.error(code, message))
  end
end
