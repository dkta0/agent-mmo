defmodule AgentMmoWeb.RunControllerTest do
  use AgentMmoWeb.ConnCase, async: true

  alias AgentMmo.Repo
  alias AgentMmo.Run

  describe "POST /api/runs" do
    test "returns 201 with run_id on valid params", %{conn: conn} do
      conn = post(conn, "/api/runs", %{scenario: "dungeon-1", score: 42})
      body = json_response(conn, 201)
      assert is_integer(body["run_id"])
    end

    test "persists run to database", %{conn: conn} do
      conn = post(conn, "/api/runs", %{scenario: "dungeon-2", score: 100, ranked: true})
      %{"run_id" => run_id} = json_response(conn, 201)

      run = Repo.get!(Run, run_id)
      assert run.scenario == "dungeon-2"
      assert run.score == 100
      assert run.ranked == true
      assert is_nil(run.user_id)
    end

    test "ranked defaults to false when not provided", %{conn: conn} do
      conn = post(conn, "/api/runs", %{scenario: "dungeon-3", score: 10})
      %{"run_id" => run_id} = json_response(conn, 201)

      run = Repo.get!(Run, run_id)
      assert run.ranked == false
    end

    test "user_id is nullable", %{conn: conn} do
      conn = post(conn, "/api/runs", %{scenario: "arena", score: 0})
      %{"run_id" => run_id} = json_response(conn, 201)
      run = Repo.get!(Run, run_id)
      assert is_nil(run.user_id)
    end

    test "returns 422 when scenario is missing", %{conn: conn} do
      conn = post(conn, "/api/runs", %{score: 10})
      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["scenario"]
    end

    test "returns 422 when score is missing", %{conn: conn} do
      conn = post(conn, "/api/runs", %{scenario: "dungeon-1"})
      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["score"]
    end

    test "returns 422 when params are empty", %{conn: conn} do
      conn = post(conn, "/api/runs", %{})
      assert %{"errors" => _errors} = json_response(conn, 422)
    end
  end
end
