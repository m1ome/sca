defmodule ScaWeb.DocsControllerTest do
  use ScaWeb.ConnCase, async: true

  test "the API documentation is served, to anyone", %{conn: conn} do
    conn = get(conn, ~p"/docs")

    assert response_content_type(conn, :html)
    assert response(conn, 200) =~ "SCA API"
  end
end
