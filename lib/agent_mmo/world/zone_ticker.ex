defmodule AgentMmo.World.ZoneTicker do
  @moduledoc "GenServer driving the 500ms tick loop for a zone."

  use GenServer

  alias AgentMmo.World.{Entity, ZoneSupervisor}
  alias AgentMmo.Player.PlayerSession
  alias AgentMmo.World.NPC
  alias AgentMmo.Quest.QuestEngine
  alias AgentMmo.World.ScenarioLoader

  @default_tick_interval_ms 500
  @map_max 99
  @map_min 0

  defstruct [:zone_id, :tick, :action_queues, :tick_interval_ms, :zone_meta]

  # Client API

  def start_link(opts) do
    zone_id = Keyword.fetch!(opts, :zone_id)
    GenServer.start_link(__MODULE__, opts, name: via_name(zone_id))
  end

  @doc "Enqueue a player action to be processed on the next tick."
  def enqueue_action(zone_id, player_id, action) do
    GenServer.cast(via_name(zone_id), {:enqueue_action, player_id, action})
  end

  defp via_name(zone_id) do
    {:via, Registry, {AgentMmo.ZoneRegistry, {:ticker, zone_id}}}
  end

  # Server callbacks

  @impl true
  def init(opts) do
    zone_id = Keyword.fetch!(opts, :zone_id)
    interval = Application.get_env(:agent_mmo, :tick_interval_ms, @default_tick_interval_ms)

    state = %__MODULE__{
      zone_id: zone_id,
      tick: 0,
      action_queues: %{},
      tick_interval_ms: interval,
      zone_meta: nil
    }

    schedule_tick(interval)
    {:ok, state}
  end

  @impl true
  def handle_cast({:enqueue_action, player_id, action}, state) do
    queue = Map.get(state.action_queues, player_id, [])
    {:noreply, %{state | action_queues: Map.put(state.action_queues, player_id, queue ++ [action])}}
  end

  @impl true
  def handle_info(:tick, state) do
    zone_meta = load_zone_meta(state)
    state = %{state | zone_meta: zone_meta}

    {new_state, acked_seqs} = process_tick(state)
    schedule_tick(state.tick_interval_ms)
    broadcast_tick(new_state, acked_seqs)
    {:noreply, new_state}
  end

  defp load_zone_meta(state) do
    ets_table = ets_name(state.zone_id)

    case :ets.whereis(ets_table) do
      :undefined -> state.zone_meta
      _ ->
        case :ets.lookup(ets_table, :zone_meta) do
          [{:zone_meta, meta}] -> meta
          _ -> state.zone_meta
        end
    end
  end

  defp process_tick(state) do
    ets_table = ets_name(state.zone_id)
    entities = read_entities(ets_table)

    {updated_entities, all_acked} =
      Enum.reduce(state.action_queues, {entities, []}, fn {player_id, actions}, {ents, acked} ->
        {new_ents, new_acked} = apply_player_actions(ents, player_id, actions, state)
        {new_ents, acked ++ new_acked}
      end)

    new_tick = state.tick + 1

    Enum.each(updated_entities, fn entity ->
      :ets.insert(ets_table, {{entity.kind, entity.id}, %{entity | updated_at: new_tick}})
    end)

    new_state = %{state | tick: new_tick, action_queues: %{}}
    {new_state, all_acked}
  end

  defp apply_player_actions(entities, player_id, actions, state) do
    player_entity_id = "player_#{player_id}"

    {updated_entities, acked} =
      Enum.reduce(actions, {entities, []}, fn action, {ents, acked} ->
        {new_ents, new_acked} = dispatch_action(action, ents, player_id, player_entity_id, state)
        {new_ents, acked ++ new_acked}
      end)

    {updated_entities, Enum.reverse(acked)}
  end

  defp dispatch_action(action, entities, player_id, player_entity_id, state) do
    case action do
      %{"action" => "move", "direction" => dir, "seq" => seq} ->
        new_ents = move_player(entities, player_entity_id, dir, state)
        safe_increment_steps(player_id)
        new_ents = check_exit_transition(new_ents, player_id, player_entity_id, state)
        check_quest_after_action(player_id, state.zone_id)
        {new_ents, [seq]}

      %{"action" => "move", "direction" => dir} ->
        new_ents = move_player(entities, player_entity_id, dir, state)
        safe_increment_steps(player_id)
        new_ents = check_exit_transition(new_ents, player_id, player_entity_id, state)
        check_quest_after_action(player_id, state.zone_id)
        {new_ents, []}

      %{"action" => "enter", "target" => exit_id} ->
        handle_enter(entities, player_id, player_entity_id, exit_id, state)
        {entities, []}

      %{"action" => "speak", "target" => npc_id} ->
        handle_speak(entities, player_id, npc_id, state)
        {entities, []}

      %{"action" => "reply", "choice" => choice_id, "npc_id" => npc_id} ->
        handle_reply(entities, player_id, npc_id, choice_id, state)
        {entities, []}

      %{"action" => "examine", "target" => target_id} ->
        handle_examine(entities, player_id, target_id)
        {entities, []}

      %{"action" => "pickup", "target" => item_id} ->
        new_ents = handle_pickup(entities, player_id, item_id, state)
        {new_ents, []}

      %{"action" => "drop", "target" => item_id} ->
        new_ents = handle_drop(entities, player_id, player_entity_id, item_id, state)
        {new_ents, []}

      %{"action" => "use", "item" => item_id} ->
        handle_use(player_id, item_id)
        {entities, []}

      %{"action" => "use", "item" => item_id, "target" => _target} ->
        handle_use(player_id, item_id)
        {entities, []}

      %{"action" => "attack", "target" => enemy_id} ->
        new_ents = handle_attack(entities, player_id, enemy_id, state)
        {new_ents, []}

      %{"action" => "flee"} ->
        new_ents = handle_flee(entities, player_id, player_entity_id, state)
        {new_ents, []}

      %{"action" => "inventory"} ->
        handle_inventory(player_id)
        {entities, []}

      %{"action" => "quests"} ->
        handle_quests(player_id)
        {entities, []}

      %{"action" => "look"} ->
        # No-op — next tick broadcast handles it
        {entities, []}

      %{"action" => "wait"} ->
        # No-op
        {entities, []}

      _ ->
        {entities, []}
    end
  end

  # ---- Action handlers ----

  defp handle_enter(entities, player_id, player_entity_id, exit_id, state) do
    player = Enum.find(entities, fn e -> e.id == player_entity_id and e.kind == :player end)
    exit_entity = find_entity_in_ets(exit_id, state.zone_id)

    if player && exit_entity && exit_entity.kind == :exit && exit_entity.exit_to do
      dest_zone = exit_entity.exit_to.zone_id
      {dest_x, dest_y} = exit_entity.exit_to.position

      # Move player entity: remove from current zone, add to destination zone
      ets_table = ets_name(state.zone_id)
      :ets.delete(ets_table, {:player, player_entity_id})

      updated_player = %{player | zone_id: dest_zone, position: {dest_x, dest_y}}
      ZoneSupervisor.join(dest_zone, player_id, updated_player)

      PlayerSession.update_zone(player_id, dest_zone)
      PlayerSession.increment_steps(player_id)

      send_player_event(player_id, %{
        type: "zone_entered",
        from_zone: state.zone_id,
        to_zone: dest_zone,
        position: %{x: dest_x, y: dest_y}
      })

      check_quest_after_action(player_id, dest_zone)
    end
  end

  defp handle_speak(entities, player_id, npc_id, _state) do
    _player = Enum.find(entities, fn e -> e.kind == :player and e.id == "player_#{player_id}" end)

    case NPC.speak(npc_id, player_id) do
      {:ok, dialogue} ->
        send_player_event(player_id, %{
          type: "dialogue",
          npc: npc_id,
          text: dialogue.greeting,
          choices: dialogue.choices
        })

      {:error, reason} ->
        send_player_event(player_id, %{type: "error", code: "NPC_ERROR", message: reason})
    end
  end

  defp handle_reply(entities, player_id, npc_id, choice_id, state) do
    _player = Enum.find(entities, fn e -> e.kind == :player and e.id == "player_#{player_id}" end)

    case NPC.reply(npc_id, player_id, choice_id) do
      {:ok, %{text: text}, flags} ->
        Enum.each(flags, fn flag ->
          PlayerSession.add_flag(player_id, flag)
        end)

        send_player_event(player_id, %{
          type: "event",
          event: "npc_spoke",
          npc: npc_id,
          text: text,
          flags: flags
        })

        check_quest_after_action(player_id, state.zone_id)

      {:error, reason} ->
        send_player_event(player_id, %{type: "error", code: "REPLY_ERROR", message: reason})
    end
  end

  defp handle_examine(entities, player_id, target_id) do
    entity = Enum.find(entities, fn e -> e.id == target_id end)

    text =
      case entity do
        nil -> "You don't see that here."
        e -> e.examine_text || "Nothing special about #{e.name || e.id}."
      end

    send_player_event(player_id, %{type: "examine", text: text})
  end

  defp handle_pickup(entities, player_id, item_id, state) do
    item = Enum.find(entities, fn e -> e.id == item_id and e.kind == :item end)

    if item do
      # Remove from ETS
      ets_table = ets_name(state.zone_id)
      :ets.delete(ets_table, {:item, item_id})

      PlayerSession.add_item(player_id, item_id)

      # Add on_pickup flags
      on_pickup_flags = (item.state || %{}) |> Map.get(:on_pickup_flags, [])

      Enum.each(on_pickup_flags, fn flag ->
        PlayerSession.add_flag(player_id, flag)
      end)

      send_player_event(player_id, %{
        type: "event",
        event: "picked_up",
        item: item_id,
        name: item.name || item_id
      })

      check_quest_after_action(player_id, state.zone_id)

      Enum.reject(entities, fn e -> e.id == item_id and e.kind == :item end)
    else
      send_player_event(player_id, %{type: "error", code: "NOT_FOUND", message: "Item not found in zone."})
      entities
    end
  end

  defp handle_drop(entities, player_id, player_entity_id, item_id, state) do
    case PlayerSession.remove_item(player_id, item_id) do
      :ok ->
        player = Enum.find(entities, fn e -> e.id == player_entity_id and e.kind == :player end)
        pos = if player, do: player.position, else: {0, 0}

        item_entity = %Entity{
          id: item_id,
          kind: :item,
          position: pos,
          zone_id: state.zone_id,
          name: item_id,
          state: %{item_type: item_id, quantity: 1},
          updated_at: state.tick
        }

        ZoneSupervisor.join(state.zone_id, item_id, item_entity)

        send_player_event(player_id, %{
          type: "event",
          event: "dropped",
          item: item_id
        })

        [item_entity | entities]

      {:error, :not_found} ->
        send_player_event(player_id, %{type: "error", code: "NOT_IN_INVENTORY", message: "Item not in inventory."})
        entities
    end
  end

  defp handle_use(player_id, item_id) do
    send_player_event(player_id, %{
      type: "event",
      event: "used",
      item: item_id
    })
  end

  defp handle_attack(entities, player_id, enemy_id, state) do
    enemy = Enum.find(entities, fn e -> e.id == enemy_id and e.kind == :enemy end)

    if enemy do
      damage = :rand.uniform(21) + 9  # 10-30

      new_health = max(0, (enemy.health || 30) - damage)

      if new_health <= 0 do
        # Enemy dead
        ets_table = ets_name(state.zone_id)
        :ets.delete(ets_table, {:enemy, enemy_id})

        # Add on_death flags
        on_death_flags = (enemy.state || %{}) |> Map.get(:on_death_flags, [])

        Enum.each(on_death_flags, fn flag ->
          PlayerSession.add_flag(player_id, flag)
        end)

        # Score penalty if penalty_on_kill
        if enemy.penalty_on_kill && enemy.penalty_on_kill > 0 do
          new_score = PlayerSession.deduct_score(player_id, enemy.penalty_on_kill, "killed_#{enemy_id}")
          send_player_event(player_id, %{
            type: "score_update",
            score: new_score,
            delta: -enemy.penalty_on_kill,
            reason: "Killed #{enemy.name || enemy_id}"
          })
        end

        broadcast_zone_event(state.zone_id, %{
          type: "combat",
          attacker: "player_#{player_id}",
          target: enemy_id,
          damage: damage,
          target_health: 0,
          killed: true
        })

        check_quest_after_action(player_id, state.zone_id)

        Enum.reject(entities, fn e -> e.id == enemy_id and e.kind == :enemy end)
      else
        # Update health
        updated_enemy = %{enemy | health: new_health}

        broadcast_zone_event(state.zone_id, %{
          type: "combat",
          attacker: "player_#{player_id}",
          target: enemy_id,
          damage: damage,
          target_health: new_health,
          killed: false
        })

        Enum.map(entities, fn e ->
          if e.id == enemy_id and e.kind == :enemy, do: updated_enemy, else: e
        end)
      end
    else
      send_player_event(player_id, %{type: "error", code: "TARGET_NOT_FOUND", message: "Enemy not found."})
      entities
    end
  end

  defp handle_flee(entities, player_id, player_entity_id, state) do
    PlayerSession.deduct_score(player_id, 5, "fled")

    new_ents = move_player(entities, player_entity_id, "south", state)

    send_player_event(player_id, %{
      type: "event",
      event: "fled"
    })

    new_ents
  end

  defp handle_inventory(player_id) do
    case PlayerSession.get_state(player_id) do
      {:ok, session} ->
        items = Enum.map(session.inventory, fn item_id ->
          %{id: item_id, name: item_id, quantity: 1}
        end)

        send_player_event(player_id, %{type: "inventory", items: items})

      _ ->
        send_player_event(player_id, %{type: "inventory", items: []})
    end
  end

  defp handle_quests(player_id) do
    case PlayerSession.get_state(player_id) do
      {:ok, session} ->
        quests = build_quest_status(session.flags)
        send_player_event(player_id, %{type: "quests", quests: quests})

      _ ->
        send_player_event(player_id, %{type: "quests", quests: []})
    end
  end

  defp build_quest_status(flags) do
    ScenarioLoader.list_scenarios()
    |> Enum.flat_map(fn _scenario ->
      :ets.tab2list(:scenario_quests)
      |> Enum.flat_map(fn {_quest_id, quest} ->
        objectives = QuestEngine.check_objectives(quest, flags)
        completed = QuestEngine.check_completion(quest, flags, "tavern")

        [%{
          id: quest.id,
          name: quest.name,
          description: quest.description,
          objectives: objectives,
          completed: completed
        }]
      end)
    end)
  end

  defp check_quest_after_action(player_id, current_zone) do
    case PlayerSession.get_state(player_id) do
      {:ok, session} ->
        # Check all quests
        :ets.tab2list(:scenario_quests)
        |> Enum.each(fn {quest_id, quest} ->
          already_complete = Enum.any?(session.quests, fn q -> q.quest_id == quest_id and q.completed end)

          unless already_complete do
            if QuestEngine.check_completion(quest, session.flags, current_zone) do
              steps = session.steps
              score = QuestEngine.compute_score(quest, steps, [])

              # Satchel bonus
              satchel_flag = quest.scoring[:satchel_flag]
              satchel_bonus = if satchel_flag && satchel_flag in session.flags do
                quest.scoring[:satchel_bonus] || 0
              else
                0
              end

              total_score = score + satchel_bonus

              PlayerSession.complete_quest(player_id, quest_id)

             send_player_event(player_id, %{
               type: "quest_complete",
               quest_id: quest_id,
               final_score: total_score,
               steps_taken: steps
             })
            end
          end
        end)

      _ -> :ok
    end
  end

  # ---- Movement ----

  defp move_player(entities, player_id, direction, state) do
    zone_width = (state.zone_meta && state.zone_meta[:width]) || @map_max
    zone_height = (state.zone_meta && state.zone_meta[:height]) || @map_max

    Enum.map(entities, fn entity ->
      if entity.id == player_id and entity.kind == :player do
        {x, y} = entity.position
        {dx, dy} = direction_delta(direction)
        new_x = clamp(x + dx, 0, zone_width - 1)
        new_y = clamp(y + dy, 0, zone_height - 1)
        %{entity | position: {new_x, new_y}}
      else
        entity
      end
    end)
  end

  defp ensure_zone_running(zone_id) do
    case Registry.lookup(AgentMmo.ZoneRegistry, {:zone_sup, zone_id}) do
      [{_pid, _}] ->
        :ok
      [] ->
        case DynamicSupervisor.start_child(
               AgentMmo.ZoneDynamicSup,
               {AgentMmo.World.ZoneSupervisor, zone_id: zone_id}
             ) do
          {:ok, _} ->
            ScenarioLoader.seed_zone_into(zone_id)
            :ok
          {:error, {:already_started, _}} -> :ok
          _ -> :ok
        end
    end
  end

  defp check_exit_transition(entities, player_id, player_entity_id, state) do
    exits = (state.zone_meta && state.zone_meta[:exits]) || []
    player = Enum.find(entities, fn e -> e.id == player_entity_id and e.kind == :player end)

    if player do
      matching_exit = Enum.find(exits, fn exit ->
        exit.position == player.position
      end)

      if matching_exit do
        dest_zone = matching_exit.destination_zone
        {dest_x, dest_y} = matching_exit.destination_position

        # Ensure destination zone is running before inserting player
        ensure_zone_running(dest_zone)

        ets_table = ets_name(state.zone_id)
        :ets.delete(ets_table, {:player, player_entity_id})

        updated_player = %{player | zone_id: dest_zone, position: {dest_x, dest_y}}
        ZoneSupervisor.join(dest_zone, player_id, updated_player)

        PlayerSession.update_zone(player_id, dest_zone)

        if matching_exit[:wrong_path_penalty] && matching_exit[:wrong_path_penalty] > 0 do
          new_score = PlayerSession.deduct_score(player_id, matching_exit[:wrong_path_penalty], "wrong_path:#{dest_zone}")
          send_player_event(player_id, %{
            type: "score_update",
            score: new_score,
            reason: "wrong_path:#{dest_zone}"
          })
        end

        send_player_event(player_id, %{
          type: "zone_entered",
          from_zone: state.zone_id,
          to_zone: dest_zone,
          position: %{x: dest_x, y: dest_y}
        })

        check_quest_after_action(player_id, dest_zone)

        Enum.reject(entities, fn e -> e.id == player_entity_id and e.kind == :player end)
      else
        entities
      end
    else
      entities
    end
  end

  defp direction_delta("north"), do: {0, -1}
  defp direction_delta("south"), do: {0, 1}
  defp direction_delta("east"), do: {1, 0}
  defp direction_delta("west"), do: {-1, 0}
  defp direction_delta("northeast"), do: {1, -1}
  defp direction_delta("northwest"), do: {-1, -1}
  defp direction_delta("southeast"), do: {1, 1}
  defp direction_delta("southwest"), do: {-1, 1}
  defp direction_delta(_), do: {0, 0}

  defp clamp(v, min, max), do: v |> max(min) |> min(max)

  defp read_entities(ets_table) do
    case :ets.whereis(ets_table) do
      :undefined ->
        []

      _ ->
        :ets.tab2list(ets_table)
        |> Enum.filter(fn {key, _} -> key != :zone_meta end)
        |> Enum.map(fn {_key, entity} -> entity end)
    end
  end

  defp find_entity_in_ets(entity_id, zone_id) do
    ets_table = ets_name(zone_id)

    case :ets.whereis(ets_table) do
      :undefined -> nil
      _ ->
        [:player, :npc, :enemy, :item, :exit]
        |> Enum.find_value(fn kind ->
          case :ets.lookup(ets_table, {kind, entity_id}) do
            [{_, entity}] -> entity
            [] -> nil
          end
        end)
    end
  end

  defp send_player_event(player_id, payload) do
    Phoenix.PubSub.broadcast(
      AgentMmo.PubSub,
      "player:#{player_id}",
      {:player_event, payload}
    )
  end

  defp broadcast_zone_event(zone_id, event) do
    Phoenix.PubSub.broadcast(
      AgentMmo.PubSub,
      "zone:#{zone_id}",
      {:zone_event, event}
    )
  end

  defp broadcast_tick(state, acked_seqs) do
    entities =
      read_entities(ets_name(state.zone_id))
      |> Enum.map(&Entity.to_json/1)

    zone_meta = state.zone_meta || %{width: 10, height: 10}

    payload = %{
      tick: state.tick,
      timestamp_ms: System.os_time(:millisecond),
      zone_id: state.zone_id,
      zone: %{
        id: state.zone_id,
        width: zone_meta[:width] || 10,
        height: zone_meta[:height] || 10
      },
      entities: entities,
      events: [],
      acked_seqs: acked_seqs
    }

    Phoenix.PubSub.broadcast(AgentMmo.PubSub, "zone:#{state.zone_id}", {:tick_broadcast, payload})
    Phoenix.PubSub.broadcast(AgentMmo.PubSub, "spectate:lobby", {:tick_broadcast, payload})
  end

  defp safe_increment_steps(player_id) do
    try do
      PlayerSession.increment_steps(player_id)
    catch
      :exit, _ -> :ok
    end
  end

  defp schedule_tick(interval), do: Process.send_after(self(), :tick, interval)

  defp ets_name(zone_id), do: :"zone_entities_#{zone_id}"
end
