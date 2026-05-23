defmodule AgentMmoWeb.SpectatorSocket do
  @moduledoc """
  Public WebSocket socket for unauthenticated spectators.

  Spectators can only join spectate:* topics (read-only). They don't need
  an API key — this socket exists specifically for homepage hero embeds and
  public observers who are not running benchmark agents.
  """

  use Phoenix.Socket

  channel "spectate:*", AgentMmoWeb.SpectateChannel
  channel "spectator:*", AgentMmoWeb.SpectateChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
