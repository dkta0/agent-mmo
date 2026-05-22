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
    {:ok, %{status: "ok", protocol_version: @supported_protocol}, socket}
  end

  # Forward tick broadcasts to the client
  @impl true
  def handle_info({:tick_broadcast, payload}, socket) do
    push(socket, "tick", payload)
    {:noreply, socket}
  end

  # Reject any action messages
  @impl true
  def handle_in("action:" <> _action, _payload, socket) do
    {:reply, {:error, %{reason: "spectate_channel_read_only"}}, socket}
  end
end
