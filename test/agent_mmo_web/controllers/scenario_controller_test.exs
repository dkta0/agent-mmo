defmodule AgentMmoWeb.ScenarioControllerTest do
  use AgentMmoWeb.ConnCase, async: true

  describe "GET /api/scenarios" do
    test "returns 200 with a list of scenarios", %{conn: conn} do
      conn = get(conn, "/api/scenarios")
      assert body = json_response(conn, 200)
      assert is_list(body)
      assert length(body) >= 1
    end

    test "each scenario has id, name, description, difficulty", %{conn: conn} do
      [scenario | _] = conn |> get("/api/scenarios") |> json_response(200)
      assert is_binary(scenario["id"])
      assert is_binary(scenario["name"])
      assert is_binary(scenario["description"])
      assert is_binary(scenario["difficulty"])
    end

    test "includes the missing_apprentice scenario", %{conn: conn} do
      body = conn |> get("/api/scenarios") |> json_response(200)
      ids = Enum.map(body, & &1["id"])
      assert "missing_apprentice" in ids
    end
  end
end
