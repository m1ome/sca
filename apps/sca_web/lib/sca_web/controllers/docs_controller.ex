defmodule ScaWeb.DocsController do
  @moduledoc """
  Serves the API documentation at `/docs`.

  The page is `apps/sca_web/priv/docs/api.html`, rendered from the blueprint by
  `mix api.docs` and committed with it — the release image has no Node in it.
  It is one self-contained file, so it is sent as it is rather than wrapped in
  the console's layout.

  No sign-in: it is a document about a public API, and a merchant's developer
  is often not the person with a console account.
  """

  use ScaWeb, :controller

  @page "docs/api.html"

  def show(conn, _params) do
    path = Application.app_dir(:sca_web, Path.join("priv", @page))

    if File.exists?(path) do
      conn |> put_resp_content_type("text/html") |> send_file(200, path)
    else
      missing(conn)
    end
  end

  # Only in a checkout where nobody has run the task yet; in a release the file
  # is part of the image.
  defp missing(conn) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(404, "<h1>Not built</h1><p>Run <code>mix api.docs</code>.</p>")
  end
end
