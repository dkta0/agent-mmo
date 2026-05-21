defmodule AgentMmo.World.Entity do
  @moduledoc "Entity struct representing a player, NPC, or item in the game world."

  @enforce_keys [:id, :kind, :position, :zone_id]
  defstruct [
    :id,
    :kind,
    :position,
    :zone_id,
    :health,
    :max_health,
    :state,
    :updated_at
  ]

  @type kind :: :player | :npc | :item
  @type position :: {x :: integer(), y :: integer()}

  @type t :: %__MODULE__{
          id: String.t(),
          kind: kind(),
          position: position(),
          zone_id: String.t(),
          health: integer(),
          max_health: integer(),
          state: map(),
          updated_at: integer()
        }

  def to_json(%__MODULE__{} = entity) do
    {x, y} = entity.position

    %{
      id: entity.id,
      kind: entity.kind,
      position: %{x: x, y: y},
      health: entity.health,
      max_health: entity.max_health,
      state: entity.state
    }
  end
end
