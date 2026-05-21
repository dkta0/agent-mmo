defmodule AgentMmoWeb.GameChannel do
  @moduledoc "Phoenix Channel for zone:* topics. Handles player connections and action messages."

  use Phoenix.Channel

  alias AgentMmo.Player.PlayerSupervisor
  alias AgentMmo.World.ZoneTicker

  @supported_protocol "1.0"
  @valid_directions ~w(north south east west northeast northwest southeast southwest)

  @impl true
  def join("zone:" <> zone_id, %{"protocol_version" => version}, socket) do
    if version != @supported_protocol do
      {:error, %{reason: "unsupported_protocol_version", supported: @supported_protocol}}
    else
      player_id = socket.id || :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)

      PlayerSupervisor.start_player(
        player_id: player_id,
        zone_id: zone_id,
        socket_pid: self()
      )

      Phoenix.PubSub.subscribe(AgentMmo.PubSub, "zone:#{zone_id}")

      socket =
        socket
        |> assign(:zone_id, zone_id)
        |> assign(:player_id, player_id)

      {:ok, %{status: "ok", protocol_version: @supported_protocol}, socket}
    end
  end

  def join("zone:" <> _zone_id, _params, _socket) do
    {:error, %{reason: "missing_protocol_version"}}
  end

  @impl true
  def handle_in("action:move", %{"direction" => direction} = payload, socket) do
    if direction in @valid_directions do
      ZoneTicker.enqueue_action(socket.assigns.zone_id, socket.assigns.player_id, payload)
      {:reply, {:ok, %{acked: true}}, socket}
    else
      {:reply, {:error, %{code: "INVALID_DIRECTION"}}, socket}
    end
  end

  def handle_in("action:move", _payload, socket) do
    {:reply, {:error, %{code: "MISSING_DIRECTION"}}, socket}
  end

  @impl true
  def handle_info({:tick_broadcast, payload}, socket) do
    push(socket, "tick", payload)
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if player_id = socket.assigns[:player_id] do
      PlayerSupervisor.stop_player(player_id)
    end

    :ok
  end
end
