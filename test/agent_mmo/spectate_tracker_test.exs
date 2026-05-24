defmodule AgentMmo.SpectateTrackerTest do
  use ExUnit.Case, async: false

  alias AgentMmo.SpectateTracker

  setup do
    # SpectateTracker is started by the application supervisor (see Application).
    # Reset its state for test isolation rather than starting a new instance.
    :ok = SpectateTracker.reset()
    %{pid: Process.whereis(SpectateTracker)}
  end

  describe "current_run/0" do
    test "returns nil when no runs active" do
      assert SpectateTracker.current_run() == nil
    end

    test "returns run after one is started" do
      SpectateTracker.run_started("p1", %{agent_name: "bot-alpha", scenario: "cave", zone_id: "cave_01"})
      run = SpectateTracker.current_run()
      assert run != nil
      assert run.player_id == "p1"
      assert run.agent_name == "bot-alpha"
      assert run.scenario == "cave"
      assert run.score == 100
    end

    test "returns nil after the only run ends" do
      SpectateTracker.run_started("p1", %{agent_name: "bot-alpha"})
      SpectateTracker.run_ended("p1")
      assert SpectateTracker.current_run() == nil
    end

    test "returns top-scoring run when multiple are active" do
      SpectateTracker.run_started("p1", %{agent_name: "low-scorer"})
      SpectateTracker.run_started("p2", %{agent_name: "high-scorer"})

      # Simulate tick update pushing p2 ahead
      Phoenix.PubSub.broadcast(AgentMmo.PubSub, "tracker:runs", {:tick_update, "p2", 250, 10, "cave_01"})
      Process.sleep(50)

      run = SpectateTracker.current_run()
      assert run.player_id == "p2"
    end
  end

  describe "ranked_runs/1" do
    test "returns empty list when no runs" do
      assert SpectateTracker.ranked_runs() == []
    end

    test "returns all active runs sorted by score desc" do
      SpectateTracker.run_started("pa", %{agent_name: "alpha"})
      SpectateTracker.run_started("pb", %{agent_name: "beta"})
      SpectateTracker.run_started("pc", %{agent_name: "gamma"})

      # Push score update for pa
      Phoenix.PubSub.broadcast(AgentMmo.PubSub, "tracker:runs", {:tick_update, "pa", 500, 5, "z1"})
      Phoenix.PubSub.broadcast(AgentMmo.PubSub, "tracker:runs", {:tick_update, "pb", 200, 20, "z2"})
      Process.sleep(50)

      [first | rest] = SpectateTracker.ranked_runs()
      assert first.player_id == "pa"
      assert first.score == 500
      assert length(rest) == 2
    end

    test "respects limit" do
      for i <- 1..5 do
        SpectateTracker.run_started("p#{i}", %{agent_name: "bot#{i}"})
      end

      assert length(SpectateTracker.ranked_runs(3)) == 3
    end
  end

  describe "run lifecycle" do
    test "ending a run removes it from ranked_runs" do
      SpectateTracker.run_started("p1", %{})
      SpectateTracker.run_started("p2", %{})
      assert length(SpectateTracker.ranked_runs()) == 2

      SpectateTracker.run_ended("p1")
      runs = SpectateTracker.ranked_runs()
      assert length(runs) == 1
      assert hd(runs).player_id == "p2"
    end

    test "tick_update updates score and steps" do
      SpectateTracker.run_started("p1", %{agent_name: "delta"})
      Phoenix.PubSub.broadcast(AgentMmo.PubSub, "tracker:runs", {:tick_update, "p1", 350, 42, "forest_01"})
      Process.sleep(50)

      run = SpectateTracker.current_run()
      assert run.score == 350
      assert run.steps == 42
      assert run.zone_id == "forest_01"
    end
  end
end
