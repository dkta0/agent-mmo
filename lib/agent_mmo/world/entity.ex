defmodule AgentMmo.World.Entity do
  @moduledoc "Entity struct representing a player, NPC, enemy, item, or exit in the game world."

  @enforce_keys [:id, :kind, :position, :zone_id]
  defstruct [
    :id,
    :kind,
    :position,
    :zone_id,
    :health,
    :max_health,
    :state,
    :updated_at,
    :name,
    :examine_text,
    is_quest_target: false,
    penalty_on_kill: nil,
    dialogue_id: nil,
    exit_to: nil,
    exit_label: nil
  ]

  @type kind :: :player | :npc | :enemy | :item | :exit
  @type position :: {x :: integer(), y :: integer()}

  @type t :: %__MODULE__{
          id: String.t(),
          kind: kind(),
          position: position(),
          zone_id: String.t(),
          health: integer() | nil,
          max_health: integer() | nil,
          state: map() | nil,
          updated_at: integer() | nil,
          name: String.t() | nil,
          examine_text: String.t() | nil,
          is_quest_target: boolean(),
          penalty_on_kill: integer() | nil,
          dialogue_id: String.t() | nil,
          exit_to: %{zone_id: String.t(), position: {integer(), integer()}} | nil,
          exit_label: String.t() | nil
        }

  def to_json(%__MODULE__{} = entity) do
    {x, y} = entity.position

    base = %{
      id: entity.id,
      type: Atom.to_string(entity.kind),
      name: entity.name || entity.id,
      position: %{x: x, y: y},
      distance: 0.0
    }

    base
    |> maybe_add_health(entity)
  end

  defp maybe_add_health(map, %{kind: :enemy, health: h, max_health: mh}) when not is_nil(h) do
    Map.merge(map, %{health: h, max_health: mh})
  end

  defp maybe_add_health(map, _), do: map
end
