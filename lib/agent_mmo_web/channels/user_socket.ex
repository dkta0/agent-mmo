defmodule AgentMmoWeb.UserSocket do
  use Phoenix.Socket

  channel "zone:*", AgentMmoWeb.GameChannel
  channel "spectate:*", AgentMmoWeb.SpectateChannel
  channel "spectator:*", AgentMmoWeb.SpectateChannel

  @impl true
  def connect(%{"api_key" => api_key}, socket, _connect_info) do
    case AgentMmo.Auth.verify_key(api_key) do
      {:ok, %AgentMmo.ApiKey{id: id}} ->
        {:ok, assign(socket, :api_key_id, id)}

      {:error, _} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info) do
    :error
  end

  @impl true
  def id(_socket), do: nil
end
