defmodule AgentMmo.RunTranscriptsTest do
  use AgentMmo.DataCase, async: true

  alias AgentMmo.{RunTranscripts, BenchmarkRun, ApiKey, Repo}

  defp fixture_run do
    {:ok, ak} = Repo.insert(%ApiKey{agent_name: "t", owner: "o", key_hash: "h", key_prefix: "tb_xx"})
    {:ok, run} = Repo.insert(%BenchmarkRun{
      api_key_id: ak.id, scenario: "x", score: 0, steps: 0, duration_ms: 0
    })
    run
  end

  test "append/3 inserts a row keyed by (run_id, tick_no)" do
    run = fixture_run()
    assert {:ok, t1} = RunTranscripts.append(run.id, 1, %{action: %{verb: "move"}, tick: %{}})
    assert t1.tick_no == 1
  end

  test "append/3 rejects duplicate tick_no for the same run" do
    run = fixture_run()
    {:ok, _} = RunTranscripts.append(run.id, 1, %{action: %{}, tick: %{}})
    assert {:error, _cs} = RunTranscripts.append(run.id, 1, %{action: %{}, tick: %{}})
  end

  test "list_for_run/1 returns rows in ascending tick order" do
    run = fixture_run()
    {:ok, _} = RunTranscripts.append(run.id, 2, %{action: %{}, tick: %{}})
    {:ok, _} = RunTranscripts.append(run.id, 1, %{action: %{}, tick: %{}})
    assert [%{tick_no: 1}, %{tick_no: 2}] = RunTranscripts.list_for_run(run.id)
  end
end
