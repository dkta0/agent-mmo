defmodule AgentMmoWeb.GameChannel do
  @moduledoc "Phoenix Channel for zone:* topics. Handles player connections and action messages."

  use Phoenix.Channel

  alias AgentMmo.Player.PlayerSupervisor
  alias AgentMmo.World.{ZoneTicker, ZoneSupervisor}

  @supported_protocol "1.0"
  @valid_directions ~w(north south east west northeast northwest southeast southwest)

  @impl true
  def join("zone:" <> zone_id, %{"protocol_version" => version}, socket) do
    if version != @supported_protocol do
      {:error, %{reason: "unsupported_protocol_version", supported: @supported_protocol}}
    else
      player_id = socket.id || :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)

      ensure_zone_started(zone_id)

      PlayerSupervisor.start_player(
        player_id: player_id,
        zone_id: zone_id,
        socket_pid: self()
      )

      Phoenix.PubSub.subscribe(AgentMmo.PubSub, "zone:#{zone_id}")
      Phoenix.PubSub.subscribe(AgentMmo.PubSub, "player:#{player_id}")

      socket =
        socket
        |> assign(:zone_id, zone_id)
        |> assign(:player_id, player_id)
        |> assign(:last_npc_id, nil)
        |> assign(:connected_at, System.monotonic_time(:millisecond))

      initial_score = case AgentMmo.Player.PlayerSession.get_state(player_id) do
        {:ok, ps} -> Map.get(ps, :score, 0)
        _ -> 0
      end

      # Notify spectator tracker that a run has started
      agent_name = socket.assigns[:api_key_id] || player_id
      AgentMmo.SpectateTracker.run_started(player_id, %{
        agent_name: agent_name,
        scenario: "benchmark",
        zone_id: zone_id
      })

      {:ok, %{status: "ok", protocol_version: @supported_protocol, player_id: player_id, score: initial_score}, socket}
    end
  end

  def join("zone:" <> _zone_id, _params, _socket) do
    {:error, %{reason: "missing_protocol_version"}}
  end

  # ---- Action handlers ----

  @impl true
  def handle_in("action:move", %{"direction" => direction} = payload, socket) do
    if direction in @valid_directions do
      ZoneTicker.enqueue_action(socket.assigns.zone_id, socket.assigns.player_id, Map.put(payload, "action", "move"))
      {:reply, {:ok, %{acked: true}}, socket}
    else
      {:reply, {:error, %{code: "INVALID_DIRECTION"}}, socket}
    end
  end

  def handle_in("action:move", _payload, socket) do
    {:reply, {:error, %{code: "MISSING_DIRECTION"}}, socket}
  end

  def handle_in("action:enter", %{"target" => _} = payload, socket) do
    enqueue(socket, Map.put(payload, "action", "enter"))
    {:reply, {:ok, %{acked: true}}, socket}
  end

  def handle_in("action:enter", _payload, socket) do
    {:reply, {:error, %{code: "MISSING_TARGET"}}, socket}
  end

  def handle_in("action:speak", %{"target" => _} = payload, socket) do
    enqueue(socket, Map.put(payload, "action", "speak"))
    {:reply, {:ok, %{acked: true}}, socket}
  end

  def handle_in("action:speak", _payload, socket) do
    {:reply, {:error, %{code: "MISSING_TARGET"}}, socket}
  end

  def handle_in("action:reply", %{"choice" => _choice_id} = payload, socket) do
    npc_id = socket.assigns[:last_npc_id]
    action = payload |> Map.put("action", "reply") |> Map.put("npc_id", npc_id)
    enqueue(socket, action)
    {:reply, {:ok, %{acked: true}}, socket}
  end

  def handle_in("action:reply", _payload, socket) do
    {:reply, {:error, %{code: "MISSING_CHOICE"}}, socket}
  end

  def handle_in("action:examine", %{"target" => _} = payload, socket) do
    enqueue(socket, Map.put(payload, "action", "examine"))
    {:reply, {:ok, %{acked: true}}, socket}
  end

  def handle_in("action:examine", _payload, socket) do
    {:reply, {:error, %{code: "MISSING_TARGET"}}, socket}
  end

  def handle_in("action:pickup", %{"target" => _} = payload, socket) do
    enqueue(socket, Map.put(payload, "action", "pickup"))
    {:reply, {:ok, %{acked: true}}, socket}
  end

  def handle_in("action:pickup", _payload, socket) do
    {:reply, {:error, %{code: "MISSING_TARGET"}}, socket}
  end

  def handle_in("action:drop", %{"item" => item} = payload, socket) do
    enqueue(socket, payload |> Map.put("action", "drop") |> Map.put("target", item))
    {:reply, {:ok, %{acked: true}}, socket}
  end

  def handle_in("action:drop", _payload, socket) do
    {:reply, {:error, %{code: "MISSING_ITEM"}}, socket}
  end

  def handle_in("action:use", %{"item" => _} = payload, socket) do
    enqueue(socket, Map.put(payload, "action", "use"))
    {:reply, {:ok, %{acked: true}}, socket}
  end

  def handle_in("action:use", _payload, socket) do
    {:reply, {:error, %{code: "MISSING_ITEM"}}, socket}
  end

  def handle_in("action:attack", %{"target" => _} = payload, socket) do
    enqueue(socket, Map.put(payload, "action", "attack"))
    {:reply, {:ok, %{acked: true}}, socket}
  end

  def handle_in("action:attack", _payload, socket) do
    {:reply, {:error, %{code: "MISSING_TARGET"}}, socket}
  end

  def handle_in("action:flee", payload, socket) do
    enqueue(socket, Map.put(payload, "action", "flee"))
    {:reply, {:ok, %{acked: true}}, socket}
  end

  def handle_in("action:inventory", payload, socket) do
    enqueue(socket, Map.put(payload, "action", "inventory"))
    {:reply, {:ok, %{acked: true}}, socket}
  end

  def handle_in("action:quests", payload, socket) do
    enqueue(socket, Map.put(payload, "action", "quests"))
    {:reply, {:ok, %{acked: true}}, socket}
  end

  def handle_in("action:look", payload, socket) do
    enqueue(socket, Map.put(payload, "action", "look"))
    {:reply, {:ok, %{acked: true}}, socket}
  end

  def handle_in("action:wait", payload, socket) do
    enqueue(socket, Map.put(payload, "action", "wait"))
    {:reply, {:ok, %{acked: true}}, socket}
  end

  # ---- PubSub message handlers ----

  @impl true
  def handle_info({:tick_broadcast, payload}, socket) do
    player_id = socket.assigns[:player_id]

    enriched =
      case AgentMmo.Player.PlayerSession.get_state(player_id) do
        {:ok, ps} ->
          # Find this player's position from the entities list
          player_entity_id = "player_#{player_id}"

          position =
            Enum.find_value(payload.entities, %{x: 0, y: 0}, fn e ->
              if e.id == player_entity_id, do: e.position, else: nil
            end)

          inventory =
            Enum.map(ps.inventory, fn item_id ->
              %{id: item_id, name: item_id, quantity: 1}
            end)

          quest_log =
            Enum.map(ps.quests, fn quest ->
              case quest do
                %{} -> quest
                id when is_binary(id) -> %{id: id, name: id, description: "", objectives: [], complete: false}
              end
            end)

          enriched_run =
            payload
            |> Map.put(:position, position)
            |> Map.put(:inventory, inventory)
            |> Map.put(:quest_log, quest_log)
            |> Map.put(:score, ps.score)
            |> Map.put(:steps, ps.steps)

          # Push score/steps update to spectator tracker
          Phoenix.PubSub.broadcast(AgentMmo.PubSub, "tracker:runs", {
            :tick_update, player_id, ps.score, ps.steps, socket.assigns.zone_id
          })

          enriched_run

        _ ->
          payload
          |> Map.put_new(:position, %{x: 0, y: 0})
          |> Map.put_new(:inventory, [])
          |> Map.put_new(:quest_log, [])
          |> Map.put_new(:score, 0)
          |> Map.put_new(:steps, 0)
      end

    push(socket, "tick", enriched)
    {:noreply, socket}
  end

  def handle_info({:player_event, %{type: "dialogue"} = payload}, socket) do
    socket = assign(socket, :last_npc_id, payload.npc)
    push(socket, "dialogue", payload)
    {:noreply, socket}
  end

  def handle_info({:player_event, %{type: "zone_entered"} = payload}, socket) do
    Phoenix.PubSub.unsubscribe(AgentMmo.PubSub, "zone:#{socket.assigns.zone_id}")
    new_zone_id = payload.to_zone
    Phoenix.PubSub.subscribe(AgentMmo.PubSub, "zone:#{new_zone_id}")
    socket = assign(socket, :zone_id, new_zone_id)
    push(socket, "event", payload)
    {:noreply, socket}
  end

  def handle_info({:player_event, payload}, socket) do
    if Map.get(payload, :type) == "quest_complete" do
      persist_benchmark_run(socket, payload)
      push(socket, "quest_complete", payload)
    else
      push(socket, "event", payload)
    end
    {:noreply, socket}
  end

  def handle_info({:zone_event, payload}, socket) do
    push(socket, "event", payload)
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if player_id = socket.assigns[:player_id] do
      PlayerSupervisor.stop_player(player_id)
      AgentMmo.SpectateTracker.run_ended(player_id)
    end

    :ok
  end

  defp enqueue(socket, action) do
    ZoneTicker.enqueue_action(socket.assigns.zone_id, socket.assigns.player_id, action)
  end

  defp persist_benchmark_run(socket, payload) do
    api_key_id = socket.assigns[:api_key_id]

    if api_key_id do
      scenario    = to_string(Map.get(payload, :quest_id, "unknown"))
      score       = Map.get(payload, :final_score, 0)
      steps       = Map.get(payload, :steps_taken, 0)
      duration_ms = System.monotonic_time(:millisecond) - socket.assigns.connected_at

      case AgentMmo.Leaderboard.record_run(api_key_id, scenario, score, steps, duration_ms) do
        {:ok, _run} ->
          Phoenix.PubSub.broadcast(AgentMmo.PubSub, "leaderboard:#{scenario}", {:leaderboard_updated, scenario})
        {:error, reason} ->
          require Logger
          Logger.warning("Failed to persist benchmark run: #{inspect(reason)}")
      end
    end
  end

  defp ensure_zone_started(zone_id) do
    case Registry.lookup(AgentMmo.ZoneRegistry, {:zone_sup, zone_id}) do
      [{_pid, _}] ->
        :ok
      [] ->
        case DynamicSupervisor.start_child(
               AgentMmo.ZoneDynamicSup,
               {ZoneSupervisor, zone_id: zone_id}
             ) do
          {:ok, _} ->
            AgentMmo.World.ScenarioLoader.seed_zone_into(zone_id)
            :ok
          {:error, {:already_started, _}} -> :ok
          {:error, reason} ->
            require Logger
            Logger.warning("Could not start zone #{zone_id}: #{inspect(reason)}")
        end
    end
  end
end
