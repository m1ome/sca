defmodule ScaAdmin.SessionController do
  @moduledoc "The login screen for our own staff, and the session it creates."

  use ScaAdmin, :controller

  alias ScaAdmin.Auth

  def new(conn, _params), do: render(conn, :new, error: nil, form_values: %{})

  def create(conn, %{"session" => %{"email" => email, "password" => password} = params}) do
    case Auth.authenticate(email, password) do
      {:ok, admin} ->
        Auth.log_in(conn, admin)

      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> render(:new, error: message(reason), form_values: Map.delete(params, "password"))
    end
  end

  def delete(conn, _params), do: Auth.log_out(conn)

  defp message(:disabled), do: "This account has been disabled."
  defp message(_reason), do: "Those details do not match an account."
end
