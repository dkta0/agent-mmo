defmodule AgentMmo.Quest.QuestEngine do
  @moduledoc "Pure-function module for quest objective tracking, completion detection, and scoring."

  @doc "Check which objectives are completed based on player flags."
  def check_objectives(quest_spec, player_flags) do
    Enum.map(quest_spec.objectives, fn obj ->
      completed = Enum.all?(obj.flags_required, fn f -> f in player_flags end)
      %{id: obj.id, completed: completed}
    end)
  end

  @doc "Check if the quest is complete (all completion trigger flags met and in trigger zone)."
  def check_completion(quest_spec, player_flags, current_zone) do
    trigger = quest_spec.completion_trigger

    current_zone == trigger.zone &&
      Enum.all?(trigger.flags_required, fn f -> f in player_flags end)
  end

  @doc "Compute score given steps and penalty events."
  def compute_score(quest_spec, steps, penalty_events) do
    scoring = quest_spec.scoring
    base = scoring.base

    penalty =
      Enum.reduce(penalty_events, 0, fn event, acc ->
        case event do
          {:rat_killed} -> acc + abs(scoring[:rat_penalty] || 0)
          {:player_died} -> acc + abs(scoring[:death_penalty] || 0)
          {:custom, amount, _reason} -> acc + abs(amount)
        end
      end)

    step_penalty =
      if steps > (scoring[:optimal_steps] || 15) do
        abs(scoring[:per_step] || 0) * (steps - (scoring[:optimal_steps] || 15))
      else
        0
      end

    max(0, base - penalty - step_penalty)
  end
end
