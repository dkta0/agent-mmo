defmodule AgentMmo.Leaderboard do
  @moduledoc "Leaderboard queries — best scores per agent per scenario."

  import Ecto.Query
  alias AgentMmo.{Repo, BenchmarkRun, ApiKey}

  @doc "Record a completed benchmark run."
  def record_run(api_key_id, scenario, score, steps, duration_ms) do
    %AgentMmo.BenchmarkRun{}
    |> AgentMmo.BenchmarkRun.changeset(%{
      api_key_id: api_key_id,
      scenario: scenario,
      score: score,
      steps: steps,
      duration_ms: duration_ms
    })
    |> Repo.insert()
  end

  @doc "Top scores for a given scenario, ordered by best_score DESC."
  def top_scores(scenario, limit \\ 50) when is_binary(scenario) do
    limit = min(limit, 100)

    Repo.all(
      from br in BenchmarkRun,
        join: ak in ApiKey,
        on: ak.id == br.api_key_id,
        where: is_nil(ak.revoked_at) and br.scenario == ^scenario,
        group_by: [ak.agent_name, ak.owner, br.scenario],
        select: %{
          agent_name: ak.agent_name,
          owner: ak.owner,
          scenario: br.scenario,
          best_score: max(br.score),
          best_steps: min(br.steps),
          best_duration_ms: min(br.duration_ms),
          total_runs: count(br.id),
          last_run_at: max(br.completed_at)
        },
        order_by: [
          desc: max(br.score),
          asc: min(br.steps),
          asc: min(br.duration_ms)
        ],
        limit: ^limit
    )
  end

  @doc "All scenarios — best entry per agent per scenario."
  def all_scenarios_top(limit \\ 50) do
    scenarios =
      Repo.all(
        from br in BenchmarkRun,
          distinct: br.scenario,
          select: br.scenario
      )

    Map.new(scenarios, fn scenario ->
      {scenario, top_scores(scenario, limit)}
    end)
  end
end
