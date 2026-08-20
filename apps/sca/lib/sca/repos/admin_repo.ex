defmodule Sca.Repos.AdminRepo do
  @moduledoc """
  Persistence for our own staff accounts.
  """

  use Sca.Repo.Base, model: Sca.Models.Admin, create_changeset: :registration_changeset

  alias Sca.Models.Admin

  @spec get_by_email(String.t()) :: {:ok, Admin.t()} | {:error, :not_found}
  def get_by_email(email) when is_binary(email) do
    get_by(email: email |> String.trim() |> String.downcase())
  end

  @spec update_password(Admin.t(), String.t()) :: {:ok, Admin.t()} | {:error, Ecto.Changeset.t()}
  def update_password(%Admin{} = admin, password) do
    admin
    |> Admin.password_changeset(%{"password" => password})
    |> Repo.update()
  end

  @doc "A page of our own staff, filtered and sorted by the console."
  @spec page(map()) :: {[Admin.t()], Flop.Meta.t()}
  def page(params), do: list(params)

  @spec track_login(Admin.t()) :: {:ok, Admin.t()} | {:error, Ecto.Changeset.t()}
  def track_login(%Admin{} = admin), do: change(admin, last_login_at: Timex.now())
end
