defmodule ScaWeb.Auth do
  @moduledoc """
  Signing a merchant's team member in and out.

  The password check lives here rather than in the domain on purpose: "is this
  the right password" is a question about the request in front of us, not about
  the business. What the domain owns is the hash (`Sca.Models.User`) and the
  scope everything else is read through (`Sca.Scope`).

  A member's email is unique inside their tenant, not across the product, so
  signing in names the merchant too.
  """

  use ScaWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Sca.Repos.TenantRepo
  alias Sca.Repos.UserRepo
  alias Sca.Scope

  @session_key :user_id

  @doc """
  Resolves merchant, email and password to a member.

  Always spends the same time whether the merchant or the member exists —
  otherwise the response time answers questions we were not asked.
  """
  @spec authenticate(String.t(), String.t(), String.t()) ::
          {:ok, Sca.Models.User.t()} | {:error, :invalid_credentials | :disabled}
  def authenticate(tenant_public_id, email, password)
      when is_binary(tenant_public_id) and is_binary(email) and is_binary(password) do
    user =
      with {:ok, tenant} <- TenantRepo.get_by_public_id(String.trim(tenant_public_id)),
           {:ok, user} <- UserRepo.get_by_email(tenant, email) do
        user
      else
        {:error, :not_found} -> nil
      end

    cond do
      not verify_password(user, password) -> {:error, :invalid_credentials}
      user.status != :active -> {:error, :disabled}
      true -> {:ok, user}
    end
  end

  def authenticate(_tenant, _email, _password), do: {:error, :invalid_credentials}

  defp verify_password(%{password_hash: hash}, password) when is_binary(hash) do
    Bcrypt.verify_pass(password, hash)
  end

  defp verify_password(_user, _password) do
    Bcrypt.no_user_verify()
    false
  end

  @doc "Starts a session, with a fresh id so a fixated one is worthless."
  def log_in(conn, user) do
    conn
    |> renew_session()
    |> put_session(@session_key, user.id)
    |> put_session(:live_socket_id, "users_sessions:#{user.id}")
    |> redirect(to: ~p"/")
  end

  @doc "Ends the session and the LiveView connections that belonged to it."
  def log_out(conn) do
    if live_socket_id = get_session(conn, :live_socket_id) do
      ScaWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> redirect(to: ~p"/log-in")
  end

  @doc "Loads the signed-in member and their tenant onto the connection."
  def fetch_current_user(conn, _opts) do
    with user_id when is_binary(user_id) <- get_session(conn, @session_key),
         {:ok, user} <- UserRepo.get(user_id),
         {:ok, tenant} <- TenantRepo.get(user.tenant_id) do
      assign_current(conn, user, tenant)
    else
      _no_session -> assign_current(conn, nil, nil)
    end
  end

  @doc "Sends anyone without a session to the login screen."
  def require_authenticated_user(conn, _opts) do
    if conn.assigns.current_user do
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
    if conn.assigns.current_user do
      conn |> redirect(to: ~p"/") |> halt()
    else
      conn
    end
  end

  @doc """
  The LiveView half of `require_authenticated_user/2`.

  A LiveView cannot read the connection, so the same three lookups happen again
  from the session token on mount.
  """
  def on_mount(:ensure_authenticated, _params, session, socket) do
    with user_id when is_binary(user_id) <- session["user_id"],
         {:ok, user} <- UserRepo.get(user_id),
         {:ok, tenant} <- TenantRepo.get(user.tenant_id) do
      {:cont,
       socket
       |> Phoenix.Component.assign(:current_user, user)
       |> Phoenix.Component.assign(:current_tenant, tenant)
       |> Phoenix.Component.assign(:current_scope, Scope.for_tenant(tenant))}
    else
      _no_session ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/log-in")}
    end
  end

  defp assign_current(conn, user, tenant) do
    conn
    |> assign(:current_user, user)
    |> assign(:current_tenant, tenant)
    |> assign(:current_scope, tenant && Scope.for_tenant(tenant))
  end

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
