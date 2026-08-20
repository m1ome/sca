defmodule ScaAdmin.Auth do
  @moduledoc """
  Signing our own staff in and out.

  Same shape as the merchant console's `ScaWeb.Auth`, with two differences: an
  admin's email is unique across the product, so there is no merchant to name,
  and there is no tenant scope — an admin sees every merchant, which is the
  whole point of this console.
  """

  use ScaAdmin, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Sca.Actions
  alias Sca.Repos.AdminRepo

  @session_key :admin_id

  @doc """
  Resolves an email and a password to a staff account.

  Always spends the same time whether the account exists — otherwise the
  response time answers questions we were not asked.
  """
  @spec authenticate(String.t(), String.t()) ::
          {:ok, Sca.Models.Admin.t()} | {:error, :invalid_credentials | :disabled}
  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    admin =
      case AdminRepo.get_by_email(email) do
        {:ok, admin} -> admin
        {:error, :not_found} -> nil
      end

    cond do
      not verify_password(admin, password) -> {:error, :invalid_credentials}
      admin.status != :active -> {:error, :disabled}
      true -> {:ok, admin}
    end
  end

  def authenticate(_email, _password), do: {:error, :invalid_credentials}

  defp verify_password(%{password_hash: hash}, password) when is_binary(hash) do
    Bcrypt.verify_pass(password, hash)
  end

  defp verify_password(_user, _password) do
    Bcrypt.no_user_verify()
    false
  end

  @doc "Starts a session, with a fresh id so a fixated one is worthless."
  def log_in(conn, admin) do
    {:ok, _admin} = Actions.Admin.track_login(admin)

    conn
    |> renew_session()
    |> put_session(@session_key, admin.id)
    |> put_session(:live_socket_id, "admins_sessions:#{admin.id}")
    |> redirect(to: ~p"/")
  end

  @doc "Ends the session and the LiveView connections that belonged to it."
  def log_out(conn) do
    if live_socket_id = get_session(conn, :live_socket_id) do
      ScaAdmin.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> redirect(to: ~p"/log-in")
  end

  @doc "Loads the signed-in staff member onto the connection."
  def fetch_current_admin(conn, _opts) do
    with admin_id when is_binary(admin_id) <- get_session(conn, @session_key),
         {:ok, admin} <- AdminRepo.get(admin_id) do
      assign(conn, :current_admin, admin)
    else
      _no_session -> assign(conn, :current_admin, nil)
    end
  end

  @doc "Sends anyone without a session to the login screen."
  def require_authenticated_admin(conn, _opts) do
    if conn.assigns.current_admin do
      conn
    else
      conn
      |> put_flash(:error, "Please sign in to continue.")
      |> redirect(to: ~p"/log-in")
      |> halt()
    end
  end

  @doc "Keeps a signed-in member away from the login screen."
  def redirect_if_authenticated(conn, _opts) do
    if conn.assigns.current_admin do
      conn |> redirect(to: ~p"/") |> halt()
    else
      conn
    end
  end

  @doc """
  The LiveView half of `require_authenticated_admin/2`.

  A LiveView cannot read the connection, so the lookup happens again from the
  session on mount.
  """
  def on_mount(:ensure_authenticated, _params, session, socket) do
    with admin_id when is_binary(admin_id) <- session["admin_id"],
         {:ok, admin} <- AdminRepo.get(admin_id) do
      {:cont, Phoenix.Component.assign(socket, :current_admin, admin)}
    else
      _no_session -> {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/log-in")}
    end
  end

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
