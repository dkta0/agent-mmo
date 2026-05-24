defmodule AgentMmoWeb.SpectateControllerTest do
  use AgentMmoWeb.ConnCase, async: false

  alias AgentMmo.SpectateTracker

  setup do
    # SpectateTracker is a singleton GenServer started by the application
    # supervisor; reset its state so cross-test pollution from concurrent
    # GameChannel tests doesn't leak in.
    :ok = SpectateTracker.reset()
    :ok
  end

  describe "GET /spectate" do
    test "returns 200 HTML with iframe-embeddable headers", %{conn: conn} do
      conn = get(conn, "/spectate")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/html"
      assert get_resp_header(conn, "x-frame-options") == ["ALLOWALL"]
      body = conn.resp_body
      assert body =~ "spectator_socket"
      assert body =~ "Agent MMO"
    end
  end

  describe "GET /api/spectate/current" do
    test "returns JSON with nil run when no active runs", %{conn: conn} do
      conn = get(conn, "/api/spectate/current")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert Map.has_key?(body, "current_run")
      assert body["current_run"] == nil
    end

    test "returns active run when one exists", %{conn: conn} do
      SpectateTracker.run_started("ctrl_p1", %{agent_name: "test-bot", scenario: "trial"})

      conn = get(conn, "/api/spectate/current")
      body = Jason.decode!(conn.resp_body)
      run = body["current_run"]
      assert run != nil
      assert run["agent_name"] == "test-bot"
      assert run["scenario"] == "trial"

      SpectateTracker.run_ended("ctrl_p1")
    end
  end

  describe "GET /api/spectate/ranked" do
    test "returns empty list when no active runs", %{conn: conn} do
      conn = get(conn, "/api/spectate/ranked")
      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["runs"] == []
    end

    test "returns active runs", %{conn: conn} do
      SpectateTracker.run_started("ctrl_q1", %{agent_name: "ranked-bot"})

      conn = get(conn, "/api/spectate/ranked")
      body = Jason.decode!(conn.resp_body)
      assert length(body["runs"]) >= 1

      SpectateTracker.run_ended("ctrl_q1")
    end

    test "respects limit param", %{conn: conn} do
      for i <- 1..5, do: SpectateTracker.run_started("ctrl_r#{i}", %{agent_name: "b#{i}"})

      conn = get(conn, "/api/spectate/ranked?limit=2")
      body = Jason.decode!(conn.resp_body)
      assert length(body["runs"]) <= 2

      for i <- 1..5, do: SpectateTracker.run_ended("ctrl_r#{i}")
    end
  end
end
