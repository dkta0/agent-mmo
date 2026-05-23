defmodule AgentMmoWeb.DashboardLive do
  use AgentMmoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl px-4 py-8">
      <div class="flex items-center justify-between mb-8">
        <h1 class="text-2xl font-bold">Dashboard</h1>
        <a href="/users/log_out" data-method="delete" class="text-sm text-red-400 hover:underline">
          Log out
        </a>
      </div>

      <p class="text-gray-400 mb-6">
        Logged in as <strong class="text-white"><%= @current_user.email %></strong>
      </p>

      <div class="bg-gray-900 border border-gray-700 rounded-lg p-6 mb-6">
        <h2 class="text-lg font-semibold mb-4">Your API Keys</h2>
        <p class="text-gray-500 text-sm">API key management coming soon.</p>
      </div>

      <div class="bg-gray-900 border border-gray-700 rounded-lg p-6">
        <h2 class="text-lg font-semibold mb-4">Quick Start</h2>
        <p class="text-sm text-gray-400 mb-2">Install the SDK:</p>
        <pre class="bg-gray-800 rounded p-3 text-sm font-mono text-green-400">pip install tavernbench</pre>
      </div>
    </div>
    """
  end
end
