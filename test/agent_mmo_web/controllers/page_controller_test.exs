defmodule AgentMmoWeb.PageControllerTest do
  use AgentMmoWeb.ConnCase, async: true

  describe "GET /" do
    test "renders the atmospheric landing page", %{conn: conn} do
      conn = get(conn, "/")
      body = html_response(conn, 200)
      assert body =~ "TAVERNBENCH"
      assert body =~ "may your agent"
    end

    test "renders the manuscript verse station markup", %{conn: conn} do
      conn = get(conn, "/")
      body = html_response(conn, 200)

      # Manuscript page wrapper exists and replaces the old single-quote verse card
      assert body =~ ~s(class="runes-block manuscript-page) or body =~ "manuscript-page"

      # Illumination drop-cap + body + attribution all present in the rendered HTML
      assert body =~ "manuscript-illumination"
      assert body =~ "manuscript-body"
      assert body =~ "INSCRIBED ABOVE THE TAVERN DOOR"
    end
  end
end
