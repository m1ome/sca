defmodule ScaWeb.SessionController do
  @moduledoc """
  The login screen and the session it creates.

  A controller rather than a LiveView because only a plain request can write a
  cookie — the form is small enough that live validation would add nothing.
  """

  use ScaWeb, :controller

  alias ScaWeb.Auth

  def new(conn, _params) do
    render(conn, :new, error: nil, form_values: %{})
  end

  def create(conn, %{"session" => params}) do
    %{"tenant" => tenant, "email" => email, "password" => password} = params

    case Auth.authenticate(tenant, email, password) do
      {:ok, user} ->
        Auth.log_in(conn, user)

      {:error, reason} ->
        # Never says which of the three was wrong.
        conn
        |> put_status(:unauthorized)
        |> render(:new, error: message(reason), form_values: Map.delete(params, "password"))
    end
  end

  def delete(conn, _params), do: Auth.log_out(conn)

  defp message(:disabled), do: "This account has been disabled. Ask an owner to re-enable it."
  defp message(_reason), do: "Those details do not match an account."
end
