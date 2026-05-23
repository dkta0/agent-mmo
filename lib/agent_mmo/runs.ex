defmodule AgentMmo.Runs do
  @moduledoc """
  Context for recording and querying game runs.
  """

  import Ecto.Query
  alias AgentMmo.{Repo, Run, TickLog, RankedSeed}

  @seed_ttl_seconds 4 * 60 * 60

  def record_run(attrs) do
    ranked = Map.get(attrs, "ranked", false) || Map.get(attrs, :ranked, false)
    if ranked, do: record_ranked_run(attrs), else: insert_run(attrs)
  end

  defp record_ranked_run(attrs) do
    user_id  = attrs["user_id"] || attrs[:user_id]
    scenario = attrs["scenario"] || attrs[:scenario]
    seed     = attrs["seed"] || attrs[:seed]
    cond do
      is_nil(user_id)  -> {:error, :user_required_for_ranked}
      is_nil(seed)     -> {:error, :seed_required_for_ranked}
      true ->
        Repo.transaction(fn ->
          with :ok <- check_ranked_rate_limit(user_id, scenario),
               {:ok, _rs} <- consume_seed(user_id, scenario, seed),
               {:ok, run}  <- insert_run(attrs) do
            run
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
    end
  end

  defp insert_run(attrs) do
    %Run{} |> Run.changeset(attrs) |> Repo.insert()
  end

  def append_tick(attrs) do
    %TickLog{} |> TickLog.changeset(attrs) |> Repo.insert()
  end

  def append_ticks(entries) when is_list(entries) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    rows = Enum.map(entries, fn e ->
      %{
        run_id:      e["run_id"]      || e[:run_id],
        tick:        e["tick"]        || e[:tick],
        action:      e["action"]      || e[:action],
        action_args: e["action_args"] || e[:action_args],
        result:      e["result"]      || e[:result]      || "ok",
        score_delta: e["score_delta"] || e[:score_delta] || 0,
        hp_after:    e["hp_after"]    || e[:hp_after],
        x:           e["x"]           || e[:x],
        y:           e["y"]           || e[:y],
        inserted_at: now
      }
    end)
    {count, _} = Repo.insert_all(TickLog, rows)
    {:ok, count}
  end

  def get_tick_logs(run_id) do
    TickLog
    |> where([t], t.run_id == ^run_id)
    |> order_by([t], t.tick)
    |> Repo.all()
  end

  def issue_ranked_seed(user_id, scenario) do
    seed = :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
    expires_at =
      DateTime.utc_now()
      |> DateTime.add(@seed_ttl_seconds, :second)
      |> DateTime.truncate(:second)
    attrs = %{"user_id" => user_id, "scenario" => scenario, "seed" => seed, "expires_at" => expires_at}
    case %RankedSeed{} |> RankedSeed.changeset(attrs) |> Repo.insert() do
      {:ok, rs} -> {:ok, %{seed: rs.seed, expires_at: rs.expires_at}}
      err       -> err
    end
  end

  def list_runs_for_user(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    Run
    |> where([r], r.user_id == ^user_id)
    |> order_by([r], desc: r.completed_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def get_run(id, opts \\ []) do
    case Repo.get(Run, id) do
      nil -> nil
      run ->
        if Keyword.get(opts, :with_ticks, false), do: Repo.preload(run, :tick_logs), else: run
    end
  end

  defp check_ranked_rate_limit(user_id, scenario) do
    today_start = Date.utc_today() |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    count =
      Run
      |> where([r], r.user_id == ^user_id and r.scenario == ^scenario and r.ranked == true and r.completed_at >= ^today_start)
      |> Repo.aggregate(:count, :id)
    if count >= 1, do: {:error, :ranked_rate_limit_exceeded}, else: :ok
  end

  defp consume_seed(user_id, scenario, seed) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    query =
      from rs in RankedSeed,
        where: rs.seed == ^seed and rs.user_id == ^user_id and rs.scenario == ^scenario
               and is_nil(rs.used_at) and rs.expires_at > ^now,
        limit: 1
    case Repo.one(query) do
      nil -> {:error, :invalid_or_expired_seed}
      rs  -> rs |> Ecto.Changeset.change(used_at: now) |> Repo.update()
    end
  end

  @doc "List the most recent runs for a user, newest first."
  def list_recent_runs_for_user(user_id, limit \\ 10) do
    Repo.all(from r in Run, where: r.user_id == ^user_id, order_by: [desc: r.inserted_at], limit: ^limit)
  end
end
