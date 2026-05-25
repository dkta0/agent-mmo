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

  describe "GET /api/runs/:id/transcript" do
    test "GET /api/runs/:id/transcript returns rows in tick order", %{conn: conn} do
      {:ok, ak} =
        AgentMmo.Repo.insert(%AgentMmo.ApiKey{
          agent_name: "t",
          owner: "o",
          key_hash: "h",
          key_prefix: "tb_xx"
        })

      {:ok, br} =
        AgentMmo.Repo.insert(%AgentMmo.BenchmarkRun{
          api_key_id: ak.id,
          scenario: "x",
          score: 1,
          steps: 1,
          duration_ms: 10
        })

      {:ok, _} =
        AgentMmo.RunTranscripts.append(br.id, 1, %{
          action: %{verb: "move"},
          tick: %{score: 1}
        })

      resp = conn |> get("/api/runs/#{br.id}/transcript") |> json_response(200)
      assert resp["run_id"] == br.id
      assert [%{"tick_no" => 1, "action" => %{"verb" => "move"}}] = resp["transcript"]
    end
  end
end
