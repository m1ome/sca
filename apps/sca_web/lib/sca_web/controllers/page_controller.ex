defmodule ScaWeb.PageController do
  use ScaWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
