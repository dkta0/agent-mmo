defmodule AgentMmoWeb.LeaderboardControllerTest do
  use AgentMmoWeb.ConnCase, async: false

  alias AgentMmo.{Repo, ApiKey, BenchmarkRun}

  defp insert_run(attrs \\ %{}) do
    {:ok, api_key} =
      Repo.insert(%ApiKey{
        key_hash: :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower),
        key_prefix: "tb_xx",
        agent_name: attrs[:agent_name] || "test-agent",
        owner: attrs[:owner] || "t@t.com"
      })

    Repo.insert!(%BenchmarkRun{
      api_key_id: api_key.id,
      scenario: attrs[:scenario] || "test",
      score: attrs[:score] || 100,
      steps: attrs[:steps] || 10,
      duration_ms: attrs[:duration_ms] || 5000,
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })

    api_key
  end

  describe "GET /api/leaderboard" do
    test "returns entries for a scenario", %{conn: conn} do
      insert_run(scenario: "leaderboard_test", score: 200)
      conn = get(conn, "/api/leaderboard?scenario=leaderboard_test")
      body = json_response(conn, 200)
      assert body["scenario"] == "leaderboard_test"
      assert length(body["entries"]) >= 1
      entry = hd(body["entries"])
      assert entry["rank"] == 1
      assert entry["best_score"] == 200
    end

    test "returns 400 without scenario param", %{conn: conn} do
      conn = get(conn, "/api/leaderboard")
      assert %{"error" => _} = json_response(conn, 400)
    end

    test "returns empty entries for unknown scenario", %{conn: conn} do
      conn = get(conn, "/api/leaderboard?scenario=unknown_scenario_xyz")
      body = json_response(conn, 200)
      assert body["entries"] == []
    end
  end
end
