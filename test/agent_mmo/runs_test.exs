defmodule AgentMmo.RunsTest do
  use AgentMmo.DataCase, async: true

  alias AgentMmo.{Runs, Run, TickLog}

  # -------------------------------------------------------------------------
  # Helpers
  # -------------------------------------------------------------------------

  defp insert_user(attrs \\ %{}) do
    {:ok, user} =
      %AgentMmo.Accounts.User{}
      |> AgentMmo.Accounts.User.registration_changeset(
        Map.merge(%{email: "test#{System.unique_integer()}@example.com", password: "Password1!"}, attrs)
      )
      |> AgentMmo.Repo.insert()

    user
  end

  defp base_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "scenario"    => "tavern_escape_v1",
        "score"       => 100,
        "steps"       => 12,
        "duration_ms" => 5000
      },
      overrides
    )
  end

  # -------------------------------------------------------------------------
  # record_run/1 — casual
  # -------------------------------------------------------------------------

  describe "record_run/1 (casual)" do
    test "inserts a run with required attrs" do
      assert {:ok, run} = Runs.record_run(base_attrs())
      assert run.scenario == "tavern_escape_v1"
      assert run.score == 100
      assert run.steps == 12
      assert run.ranked == false
    end

    test "accepts optional user_id" do
      user = insert_user()
      assert {:ok, run} = Runs.record_run(base_attrs(%{"user_id" => user.id}))
      assert run.user_id == user.id
    end

    test "accepts replay_data" do
      replay = %{"ticks" => [%{"tick" => 1, "action" => "move"}]}
      assert {:ok, run} = Runs.record_run(base_attrs(%{"replay_data" => replay}))
      assert run.replay_data["ticks"] != nil
    end

    test "returns error for missing scenario" do
      attrs = base_attrs() |> Map.delete("scenario")
      assert {:error, changeset} = Runs.record_run(attrs)
      assert %{scenario: [_]} = errors_on(changeset)
    end

    test "returns error for negative score" do
      assert {:error, _cs} = Runs.record_run(base_attrs(%{"score" => -1}))
    end

    test "no rate limit on casual runs — same user can run same scenario twice" do
      user = insert_user()
      assert {:ok, _} = Runs.record_run(base_attrs(%{"user_id" => user.id}))
      assert {:ok, _} = Runs.record_run(base_attrs(%{"user_id" => user.id}))
    end
  end

  # -------------------------------------------------------------------------
  # record_run/1 — ranked
  # -------------------------------------------------------------------------

  describe "record_run/1 (ranked)" do
    test "requires user_id" do
      assert {:error, :user_required_for_ranked} =
        Runs.record_run(base_attrs(%{"ranked" => true, "seed" => "abc"}))
    end

    test "requires seed" do
      user = insert_user()
      assert {:error, :seed_required_for_ranked} =
        Runs.record_run(base_attrs(%{"ranked" => true, "user_id" => user.id}))
    end

    test "rejects invalid seed" do
      user = insert_user()
      attrs = base_attrs(%{"ranked" => true, "user_id" => user.id, "seed" => "badseed"})
      assert {:error, :invalid_or_expired_seed} = Runs.record_run(attrs)
    end

    test "accepts valid seed and records run" do
      user = insert_user()
      {:ok, %{seed: seed}} = Runs.issue_ranked_seed(user.id, "tavern_escape_v1")
      attrs = base_attrs(%{"ranked" => true, "user_id" => user.id, "seed" => seed})
      assert {:ok, run} = Runs.record_run(attrs)
      assert run.ranked == true
      assert run.seed == seed
    end

    test "seed is single-use: second submission with same seed fails" do
      user = insert_user()
      {:ok, %{seed: seed}} = Runs.issue_ranked_seed(user.id, "tavern_escape_v1")
      attrs = base_attrs(%{"ranked" => true, "user_id" => user.id, "seed" => seed})
      assert {:ok, _} = Runs.record_run(attrs)

      # Second attempt with same seed must fail
      assert {:error, _} = Runs.record_run(attrs)
    end

    test "rate limit: second ranked run for same scenario today is rejected" do
      user = insert_user()

      {:ok, %{seed: seed1}} = Runs.issue_ranked_seed(user.id, "tavern_escape_v1")
      assert {:ok, _} = Runs.record_run(
        base_attrs(%{"ranked" => true, "user_id" => user.id, "seed" => seed1})
      )

      # Issue a second seed — but the rate limit blocks it
      {:ok, %{seed: seed2}} = Runs.issue_ranked_seed(user.id, "tavern_escape_v1")
      assert {:error, :ranked_rate_limit_exceeded} =
        Runs.record_run(base_attrs(%{"ranked" => true, "user_id" => user.id, "seed" => seed2}))
    end

    test "rate limit is per-scenario: different scenario allowed" do
      user = insert_user()

      {:ok, %{seed: seed1}} = Runs.issue_ranked_seed(user.id, "scenario_a")
      assert {:ok, _} = Runs.record_run(
        base_attrs(%{"ranked" => true, "user_id" => user.id, "seed" => seed1, "scenario" => "scenario_a"})
      )

      {:ok, %{seed: seed2}} = Runs.issue_ranked_seed(user.id, "scenario_b")
      assert {:ok, _} = Runs.record_run(
        base_attrs(%{"ranked" => true, "user_id" => user.id, "seed" => seed2, "scenario" => "scenario_b"})
      )
    end

    test "rate limit is per-user: different user can run same scenario" do
      user1 = insert_user()
      user2 = insert_user()

      {:ok, %{seed: seed1}} = Runs.issue_ranked_seed(user1.id, "tavern_escape_v1")
      assert {:ok, _} = Runs.record_run(
        base_attrs(%{"ranked" => true, "user_id" => user1.id, "seed" => seed1})
      )

      {:ok, %{seed: seed2}} = Runs.issue_ranked_seed(user2.id, "tavern_escape_v1")
      assert {:ok, _} = Runs.record_run(
        base_attrs(%{"ranked" => true, "user_id" => user2.id, "seed" => seed2})
      )
    end
  end

  # -------------------------------------------------------------------------
  # Seed issuance
  # -------------------------------------------------------------------------

  describe "issue_ranked_seed/2" do
    test "returns a seed token and expiry" do
      user = insert_user()
      assert {:ok, %{seed: seed, expires_at: exp}} =
        Runs.issue_ranked_seed(user.id, "tavern_escape_v1")
      assert is_binary(seed)
      assert String.length(seed) > 10
      assert DateTime.compare(exp, DateTime.utc_now()) == :gt
    end
  end

  # -------------------------------------------------------------------------
  # Tick log
  # -------------------------------------------------------------------------

  describe "append_tick/1" do
    setup do
      {:ok, run} = Runs.record_run(base_attrs())
      {:ok, run: run}
    end

    test "inserts a tick entry", %{run: run} do
      attrs = %{
        "run_id"      => run.id,
        "tick"        => 1,
        "action"      => "move",
        "action_args" => %{"direction" => "north"},
        "result"      => "ok",
        "score_delta" => -5,
        "x"           => 3,
        "y"           => 4
      }
      assert {:ok, log} = Runs.append_tick(attrs)
      assert log.run_id == run.id
      assert log.tick == 1
      assert log.action == "move"
      assert log.score_delta == -5
    end

    test "returns error for missing required fields", %{run: run} do
      assert {:error, changeset} = Runs.append_tick(%{"run_id" => run.id})
      assert %{tick: [_], action: [_]} = errors_on(changeset)
    end

    test "rejects tick <= 0", %{run: run} do
      attrs = %{"run_id" => run.id, "tick" => 0, "action" => "move", "result" => "ok"}
      assert {:error, _} = Runs.append_tick(attrs)
    end
  end

  describe "append_ticks/1" do
    test "bulk inserts multiple tick entries" do
      {:ok, run} = Runs.record_run(base_attrs())

      entries = Enum.map(1..5, fn i ->
        %{"run_id" => run.id, "tick" => i, "action" => "move", "result" => "ok",
          "score_delta" => -1, "x" => i, "y" => i}
      end)

      assert {:ok, 5} = Runs.append_ticks(entries)
      logs = Runs.get_tick_logs(run.id)
      assert length(logs) == 5
      assert Enum.map(logs, & &1.tick) == [1, 2, 3, 4, 5]
    end
  end

  describe "get_tick_logs/1" do
    test "returns logs ordered by tick" do
      {:ok, run} = Runs.record_run(base_attrs())

      Runs.append_tick(%{"run_id" => run.id, "tick" => 3, "action" => "attack", "result" => "ok"})
      Runs.append_tick(%{"run_id" => run.id, "tick" => 1, "action" => "move",   "result" => "ok"})
      Runs.append_tick(%{"run_id" => run.id, "tick" => 2, "action" => "speak",  "result" => "ok"})

      logs = Runs.get_tick_logs(run.id)
      assert Enum.map(logs, & &1.tick) == [1, 2, 3]
    end
  end

  # -------------------------------------------------------------------------
  # get_run/2
  # -------------------------------------------------------------------------

  describe "get_run/2" do
    test "returns nil for unknown id" do
      assert is_nil(Runs.get_run(999_999))
    end

    test "returns run without ticks by default" do
      {:ok, run} = Runs.record_run(base_attrs())
      fetched = Runs.get_run(run.id)
      assert fetched.id == run.id
      # tick_logs should NOT be preloaded
      assert %Ecto.Association.NotLoaded{} = fetched.tick_logs
    end

    test "preloads tick_logs when with_ticks: true" do
      {:ok, run} = Runs.record_run(base_attrs())
      Runs.append_tick(%{"run_id" => run.id, "tick" => 1, "action" => "move", "result" => "ok"})

      fetched = Runs.get_run(run.id, with_ticks: true)
      assert length(fetched.tick_logs) == 1
    end
  end
end
