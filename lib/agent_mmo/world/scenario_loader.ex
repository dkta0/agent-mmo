defmodule AgentMmo.World.ScenarioLoader do
  @moduledoc """
  GenServer that loads scenario YAML files at startup and seeds ETS tables.
  Stores quest specs and scenario metadata for use by ZoneTicker and QuestEngine.
  """

  use GenServer

  require Logger

  alias AgentMmo.World.{Entity, ZoneSupervisor}

  @scenarios_table :scenarios
  @quests_table :scenario_quests

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @zone_data_table :scenario_zone_data

  def get_quest(quest_id) do
    case :ets.lookup(@quests_table, quest_id) do
      [{^quest_id, quest}] -> {:ok, quest}
      [] -> {:error, :not_found}
    end
  end

  def list_scenarios do
    :ets.tab2list(@scenarios_table)
    |> Enum.map(fn {_id, scenario} -> Map.take(scenario, [:id, :name, :description, :start_zone]) end)
  end

  @doc "Re-seed a zone that was started on-demand (lazy zone start). Safe to call multiple times."
  def seed_zone_into(zone_id) do
    case :ets.lookup(@zone_data_table, zone_id) do
      [{^zone_id, zone_data}] -> seed_zone(zone_id, zone_data)
      [] -> :ok
    end
  end

  def get_scenario(scenario_id) do
    case :ets.lookup(@scenarios_table, scenario_id) do
      [{^scenario_id, scenario}] -> {:ok, scenario}
      [] -> {:error, :not_found}
    end
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    :ets.new(@scenarios_table, [:set, :public, :named_table, {:read_concurrency, true}])
    :ets.new(@quests_table, [:set, :public, :named_table, {:read_concurrency, true}])
    :ets.new(@zone_data_table, [:set, :public, :named_table, {:read_concurrency, true}])

    load_scenarios()

    {:ok, %{}}
  end

  defp load_scenarios do
    scenario_dir = :code.priv_dir(:agent_mmo) |> Path.join("scenarios")

    case File.ls(scenario_dir) do
      {:ok, files} ->
        Enum.each(files, fn file ->
          if Path.extname(file) in [".yaml", ".yml"] do
            path = Path.join(scenario_dir, file)

            case YamlElixir.read_from_file(path) do
              {:ok, data} ->
                load_scenario(data)

              {:error, err} ->
                Logger.error("Failed to load scenario #{file}: #{inspect(err)}")
            end
          end
        end)

      {:error, err} ->
        Logger.warning("Could not list scenarios dir: #{inspect(err)}")
    end
  end

  defp load_scenario(data) do
    scenario_id = data["id"]
    Logger.info("Loading scenario: #{scenario_id}")

    zones = data["zones"] || %{}

    # Seed each zone's entities into already-running ZoneSupervisors
    Enum.each(zones, fn {zone_id, zone_data} ->
      :ets.insert(@zone_data_table, {zone_id, zone_data})
      seed_zone(zone_id, zone_data)
    end)

    # Parse and store quest
    quest_data = data["quest"]
    scoring_data = data["scoring"]

    if quest_data do
      quest_spec = parse_quest(quest_data, scoring_data)
      :ets.insert(@quests_table, {quest_spec.id, quest_spec})
    end

    # Store scenario summary
    spawn_pos = parse_position(data["player_spawn"])

    scenario = %{
      id: scenario_id,
      name: data["name"],
      description: data["description"],
      start_zone: data["start_zone"],
      player_spawn: spawn_pos
    }

    :ets.insert(@scenarios_table, {scenario_id, scenario})
  end

  defp seed_zone(zone_id, zone_data) do
    width = zone_data["width"] || 10
    height = zone_data["height"] || 10

    exits_raw = zone_data["exits"] || []
    exits_meta =
      Enum.map(exits_raw, fn e ->
        pos = parse_position(e["position"])
        dest_pos = parse_position(e["destination_position"])

        %{
          id: e["id"],
          position: pos,
          label: e["label"] || "",
          destination_zone: e["destination_zone"],
          destination_position: dest_pos,
          wrong_path: e["wrong_path"] || false,
          wrong_path_penalty: e["wrong_path_penalty"] || 0
        }
      end)

    # Only seed entities if ZoneSupervisor has already created the ETS table for this zone.
    # Zones that haven't been started yet are seeded lazily when the zone boots.
    table = :"zone_entities_#{zone_id}"

    if :ets.whereis(table) != :undefined do
      :ets.insert(table, {:zone_meta, %{
        zone_id: zone_id,
        width: width,
        height: height,
        exits: exits_meta
      }})

      # Seed exits as entities
      Enum.each(exits_raw, fn e ->
        pos = parse_position(e["position"])
        dest_pos = parse_position(e["destination_position"])

        entity = %Entity{
          id: e["id"],
          kind: :exit,
          position: pos,
          zone_id: zone_id,
          name: e["label"] || e["id"],
          examine_text: "An exit leading to #{e["label"] || e["destination_zone"]}.",
          exit_to: %{zone_id: e["destination_zone"], position: dest_pos},
          exit_label: e["label"],
          state: %{},
          updated_at: 0
        }

        ZoneSupervisor.join(zone_id, entity.id, entity)
      end)

      # Seed NPCs
      npcs = zone_data["npcs"] || []

      Enum.each(npcs, fn npc ->
        pos = parse_position(npc["position"])
        dialogue = parse_dialogue(npc["dialogue"])

        entity = %Entity{
          id: npc["id"],
          kind: :npc,
          position: pos,
          zone_id: zone_id,
          name: npc["name"] || npc["id"],
          examine_text: npc["examine_text"],
          dialogue_id: npc["id"],
          state: %{display_name: npc["name"] || npc["id"], animation: "idle"},
          updated_at: 0
        }

        ZoneSupervisor.join(zone_id, entity.id, entity)

        npc_opts = [
          id: npc["id"],
          name: npc["name"] || npc["id"],
          position: pos,
          zone_id: zone_id,
          dialogue: dialogue
        ]

        case AgentMmo.World.ZoneNPCSup.start_npc(zone_id, npc_opts) do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
          err -> Logger.warning("Failed to start NPC #{npc["id"]}: #{inspect(err)}")
        end
      end)

      # Seed enemies
      enemies = zone_data["enemies"] || []

      Enum.each(enemies, fn enemy ->
        pos = parse_position(enemy["position"])

        on_death_flags =
          case enemy["on_death"] do
            %{"flags" => flags} -> flags
            _ -> []
          end

        entity = %Entity{
          id: enemy["id"],
          kind: :enemy,
          position: pos,
          zone_id: zone_id,
          health: enemy["health"] || 30,
          max_health: enemy["max_health"] || 30,
          name: enemy["name"] || enemy["id"],
          examine_text: enemy["examine_text"],
          is_quest_target: enemy["is_quest_target"] || false,
          penalty_on_kill: enemy["penalty_on_kill"],
          state: %{animation: "idle", on_death_flags: on_death_flags},
          updated_at: 0
        }

        ZoneSupervisor.join(zone_id, entity.id, entity)
      end)

      # Seed items
      items = zone_data["items"] || []

      Enum.each(items, fn item ->
        pos = parse_position(item["position"])

        on_pickup_flags =
          case item["on_pickup"] do
            %{"flags" => flags} -> flags
            _ -> []
          end

        entity = %Entity{
          id: item["id"],
          kind: :item,
          position: pos,
          zone_id: zone_id,
          name: item["name"] || item["id"],
          examine_text: item["description"],
          state: %{item_type: item["id"], quantity: 1, on_pickup_flags: on_pickup_flags},
          updated_at: 0
        }

        ZoneSupervisor.join(zone_id, entity.id, entity)
      end)
    end
  end

  defp parse_dialogue(nil), do: %{greeting: "...", choices: []}

  defp parse_dialogue(dialogue_data) do
    choices =
      (dialogue_data["choices"] || [])
      |> Enum.map(fn c ->
        %{
          id: c["id"],
          text: c["text"] || "",
          response: c["response"] || "",
          flags: c["flags"] || []
        }
      end)

    %{
      greeting: dialogue_data["greeting"] || "",
      choices: choices
    }
  end

  defp parse_quest(quest_data, scoring_data) do
    objectives =
      (quest_data["objectives"] || [])
      |> Enum.map(fn obj ->
        %{
          id: obj["id"],
          description: obj["description"] || "",
          flags_required: obj["flags_required"] || [],
          optional: obj["optional"] || false
        }
      end)

    trigger = quest_data["completion_trigger"] || %{}

    completion_trigger = %{
      zone: trigger["zone"] || "",
      flags_required: trigger["flags_required"] || []
    }

    scoring = parse_scoring(scoring_data)

    %{
      id: quest_data["id"],
      name: quest_data["name"] || "",
      description: quest_data["description"] || "",
      objectives: objectives,
      completion_trigger: completion_trigger,
      scoring: scoring
    }
  end

  defp parse_scoring(nil), do: %{base: 100, per_step: 0, rat_penalty: 0, death_penalty: 0, speed_bonus: nil}

  defp parse_scoring(scoring) do
    speed_bonus =
      case scoring["speed_bonus"] do
        %{"threshold_steps" => t} ->
          %{threshold_steps: t, bonus: scoring["speed_bonus"]["bonus"] || 0}
        _ -> nil
      end

    %{
      base: scoring["base"] || 100,
      per_step: scoring["per_step_over_optimal"] || 0,
      rat_penalty: scoring["rat_penalty"] || 0,
      death_penalty: scoring["death_penalty"] || 0,
      wrong_path_penalty: scoring["wrong_path_penalty"] || 0,
      satchel_bonus: scoring["satchel_bonus"] || 0,
      satchel_flag: scoring["satchel_flag"],
      optimal_steps: scoring["optimal_steps"] || 15,
      speed_bonus: speed_bonus
    }
  end

  defp parse_position(nil), do: {0, 0}

  defp parse_position(pos) when is_map(pos) do
    x = pos["x"] || pos[:x] || 0
    y = pos["y"] || pos[:y] || 0
    {x, y}
  end

  defp parse_position(_), do: {0, 0}
end
