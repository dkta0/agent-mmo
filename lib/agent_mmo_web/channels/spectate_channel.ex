defmodule AgentMmoWeb.SpectateChannel do
  @moduledoc "Read-only spectator channel for spectate:* and spectator:* topics. Subscribes to PubSub tick broadcasts."

  use Phoenix.Channel

  @supported_protocol "1.0"

  @impl true
  def join(topic, %{"protocol_version" => version}, socket) when is_binary(topic) do
    if version != @supported_protocol do
      {:error, %{reason: "unsupported_protocol_version", supported: @supported_protocol}}
    else
      zone_id = extract_zone_id(topic)
      do_join(zone_id, socket)
    end
  end

  def join(topic, _params, socket) when is_binary(topic) do
    # Allow joins without protocol_version for spectator clients
    zone_id = extract_zone_id(topic)
    do_join(zone_id, socket)
  end

  defp extract_zone_id(topic) do
    case String.split(topic, ":", parts: 2) do
      [_prefix, zone_id] -> zone_id
      _ -> "lobby"
    end
  end

  defp do_join(zone_id, socket) do
    if zone_id == "lobby" do
      # Lobby spectators subscribe to a global broadcast topic
      Phoenix.PubSub.subscribe(AgentMmo.PubSub, "spectate:lobby")
    else
      Phoenix.PubSub.subscribe(AgentMmo.PubSub, "zone:#{zone_id}")
    end

    socket = assign(socket, :zone_id, zone_id)

    reply = %{
      status: "ok",
      protocol_version: @supported_protocol,
      current_run: AgentMmo.SpectateTracker.current_run()
    }

    {:ok, reply, socket}
  end

  # Forward tick broadcasts to the client
  @impl true
  def handle_info({:tick_broadcast, payload}, socket) do
    push(socket, "tick", payload)
    {:noreply, socket}
  end

  # Forward spectator-room updates to the client as `current_run`
  def handle_info({:spectate_update, run}, socket) do
    push(socket, "current_run", %{run: run})
    {:noreply, socket}
  end

  # Reject any action messages (read-only channel)
  @impl true
  def handle_in("action:" <> _action, _payload, socket) do
    {:reply, {:error, %{reason: "spectate_channel_read_only"}}, socket}
  end

  # Snapshot queries
  def handle_in("get:current_run", _payload, socket) do
    {:reply, {:ok, %{run: AgentMmo.SpectateTracker.current_run()}}, socket}
  end

  def handle_in("get:ranked_runs", payload, socket) do
    limit =
      case Map.get(payload, "limit") do
        n when is_integer(n) and n > 0 -> min(n, 20)
        _ -> 10
      end

    {:reply, {:ok, %{runs: AgentMmo.SpectateTracker.ranked_runs(limit)}}, socket}
  end
end
