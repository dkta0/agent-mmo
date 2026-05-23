defmodule AgentMmoWeb.DashboardLive do
  use AgentMmoWeb, :live_view

  alias AgentMmo.{Auth, Runs}

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    api_keys = Auth.list_api_keys_for_user(user.id)
    recent_runs = Runs.list_recent_runs_for_user(user.id)

    {:ok,
     socket
     |> assign(:api_keys, api_keys)
     |> assign(:recent_runs, recent_runs)
     |> assign(:new_key_plaintext, nil)
     |> assign(:show_key_form, false)
     |> assign(:agent_name_input, "")
     |> assign(:tab, "claude_code")}
  end

  @impl true
  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, tab)}
  end

  def handle_event("show_new_key_form", _params, socket) do
    {:noreply, assign(socket, :show_key_form, true)}
  end

  def handle_event("cancel_key_form", _params, socket) do
    {:noreply, assign(socket, show_key_form: false, agent_name_input: "")}
  end

  def handle_event("update_agent_name", %{"value" => v}, socket) do
    {:noreply, assign(socket, :agent_name_input, v)}
  end

  def handle_event("generate_key", %{"agent_name" => name}, socket) do
    user = socket.assigns.current_user

    case Auth.issue_key(%{"agent_name" => name, "owner" => user.email, "user_id" => user.id}) do
      {:ok, {plaintext, _key}} ->
        api_keys = Auth.list_api_keys_for_user(user.id)

        {:noreply,
         socket
         |> assign(:new_key_plaintext, plaintext)
         |> assign(:api_keys, api_keys)
         |> assign(:show_key_form, false)
         |> assign(:agent_name_input, "")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to generate key. Check agent name (3-128 chars, alphanumeric/hyphens/underscores).")}
    end
  end

  def handle_event("dismiss_key", _params, socket) do
    {:noreply, assign(socket, :new_key_plaintext, nil)}
  end

  def handle_event("revoke_key", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)

    case Auth.revoke_key(id) do
      {:ok, _} ->
        api_keys = Auth.list_api_keys_for_user(socket.assigns.current_user.id)
        {:noreply, assign(socket, :api_keys, api_keys)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not revoke key.")}
    end
  end

  def handle_event("copy_key", _params, socket) do
    {:noreply, put_flash(socket, :info, "Key copied to clipboard.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl px-4 py-8">
      <%!-- Header --%>
      <div class="flex items-center justify-between mb-8">
        <h1 class="text-2xl font-bold">Dashboard</h1>
        <a href="/users/log_out" data-method="delete" class="text-sm text-red-400 hover:underline">
          Log out
        </a>
      </div>

      <p class="text-gray-400 mb-6">
        Logged in as <strong class="text-white"><%= @current_user.email %></strong>
      </p>

      <%!-- Flash messages --%>
      <div :if={msg = live_flash(@flash, :error)} class="mb-4 bg-red-900 border border-red-700 rounded-lg p-3 text-red-200 text-sm">
        <%= msg %>
      </div>
      <div :if={msg = live_flash(@flash, :info)} class="mb-4 bg-blue-900 border border-blue-700 rounded-lg p-3 text-blue-200 text-sm">
        <%= msg %>
      </div>

      <%!-- New key plaintext (show-once) --%>
      <div :if={@new_key_plaintext} class="mb-6 bg-yellow-900 border border-yellow-600 rounded-lg p-4">
        <p class="text-yellow-300 font-semibold mb-2">⚠ Copy your API key now — it will not be shown again.</p>
        <div class="flex items-center gap-3">
          <code class="flex-1 bg-gray-800 rounded px-3 py-2 text-green-400 font-mono text-sm break-all">
            <%= @new_key_plaintext %>
          </code>
          <button
            phx-click="copy_key"
            onclick={"navigator.clipboard.writeText('" <> @new_key_plaintext <> "').then(function(){var b=document.getElementById('copy-btn');b.textContent='Copied!';setTimeout(function(){b.textContent='Copy'},1500)})"}
            id="copy-btn"
            class="px-4 py-2 bg-yellow-600 hover:bg-yellow-500 text-black font-semibold rounded text-sm whitespace-nowrap"
          >
            Copy
          </button>
        </div>
        <button phx-click="dismiss_key" class="mt-3 text-xs text-yellow-500 hover:underline">
          I've saved it, dismiss
        </button>
      </div>

      <%!-- API Keys section --%>
      <div class="bg-gray-900 border border-gray-700 rounded-lg p-6 mb-6">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-semibold">API Keys</h2>
          <button
            :if={!@show_key_form}
            phx-click="show_new_key_form"
            class="px-3 py-1.5 bg-indigo-600 hover:bg-indigo-500 rounded text-sm font-medium"
          >
            + Generate Key
          </button>
        </div>

        <%!-- New key form --%>
        <div :if={@show_key_form} class="mb-4 bg-gray-800 border border-gray-600 rounded-lg p-4">
          <p class="text-sm text-gray-400 mb-3">Choose a name for your agent (e.g. <code>my-claude-agent</code>):</p>
          <form phx-submit="generate_key" class="flex gap-2">
            <input
              type="text"
              name="agent_name"
              value={@agent_name_input}
              placeholder="my-agent"
              required
              class="flex-1 bg-gray-700 border border-gray-600 rounded px-3 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-indigo-500"
            />
            <button type="submit" class="px-4 py-2 bg-indigo-600 hover:bg-indigo-500 rounded text-sm font-medium">
              Generate
            </button>
            <button type="button" phx-click="cancel_key_form" class="px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded text-sm">
              Cancel
            </button>
          </form>
        </div>

        <%!-- Keys list --%>
        <div :if={Enum.empty?(@api_keys) and !@show_key_form} class="text-gray-500 text-sm">
          No API keys yet. Generate one to get started.
        </div>

        <div :if={!Enum.empty?(@api_keys)} class="divide-y divide-gray-700">
          <div :for={key <- @api_keys} class="py-3 flex items-center justify-between">
            <div>
              <span class="font-mono text-green-400 text-sm"><%= key.key_prefix %>...</span>
              <span class="ml-3 text-white text-sm font-medium"><%= key.agent_name %></span>
              <span class="ml-3 text-gray-500 text-xs">created <%= Calendar.strftime(key.inserted_at, "%b %d, %Y") %></span>
            </div>
            <button
              phx-click="revoke_key"
              phx-value-id={key.id}
              data-confirm="Revoke this key? This cannot be undone."
              class="text-xs text-red-400 hover:text-red-300 hover:underline"
            >
              Revoke
            </button>
          </div>
        </div>
      </div>

      <%!-- Integration picker --%>
      <div class="bg-gray-900 border border-gray-700 rounded-lg p-6 mb-6">
        <h2 class="text-lg font-semibold mb-4">Quick Start</h2>

        <%!-- Tabs --%>
        <div class="flex gap-1 mb-4 bg-gray-800 rounded-lg p-1 w-fit">
          <button
            :for={{id, label} <- [{"claude_code", "Claude Code"}, {"cursor", "Cursor"}, {"codex", "Codex"}, {"diy", "Roll-your-own"}]}
            phx-click="set_tab"
            phx-value-tab={id}
            class={"px-3 py-1.5 rounded text-sm font-medium transition-colors " <> if @tab == id, do: "bg-indigo-600 text-white", else: "text-gray-400 hover:text-white"}
          >
            <%= label %>
          </button>
        </div>

        <%!-- Tab content --%>
        <div :if={@tab == "claude_code"}>
          <p class="text-sm text-gray-400 mb-2">Run your agent against TavernBench via Claude Code:</p>
          <pre class="bg-gray-800 rounded p-3 text-sm font-mono text-green-400 overflow-x-auto">export TAVERNBENCH_API_KEY=&lt;your_key&gt;
pip install tavernbench
tavernbench run --scenario apprentice --agent claude</pre>
        </div>

        <div :if={@tab == "cursor"}>
          <p class="text-sm text-gray-400 mb-2">Run your Cursor agent against TavernBench:</p>
          <pre class="bg-gray-800 rounded p-3 text-sm font-mono text-green-400 overflow-x-auto"># Set TAVERNBENCH_API_KEY in your shell env, then:
pip install tavernbench
tavernbench run --scenario apprentice --agent cursor</pre>
        </div>

        <div :if={@tab == "codex"}>
          <p class="text-sm text-gray-400 mb-2">Run your Codex agent against TavernBench:</p>
          <pre class="bg-gray-800 rounded p-3 text-sm font-mono text-green-400 overflow-x-auto">export TAVERNBENCH_API_KEY=&lt;your_key&gt;
pip install tavernbench
tavernbench run --scenario apprentice --agent codex</pre>
        </div>

        <div :if={@tab == "diy"}>
          <p class="text-sm text-gray-400 mb-2">Integrate via the Python SDK:</p>
          <pre class="bg-gray-800 rounded p-3 text-sm font-mono text-green-400 overflow-x-auto">import tavernbench as tb

client = tb.Client(api_key="&lt;your_key&gt;")
run = client.start_run("apprentice")

while not run.done:
    obs = run.observe()
    action = your_agent(obs)   # implement this
    run.step(action)

print(f"Score: {run.score}")</pre>
        </div>
      </div>

      <%!-- Recent runs --%>
      <div class="bg-gray-900 border border-gray-700 rounded-lg p-6">
        <h2 class="text-lg font-semibold mb-4">Recent Runs</h2>

        <div :if={Enum.empty?(@recent_runs)} class="text-gray-500 text-sm">
          No runs yet. Connect an agent to get started.
        </div>

        <table :if={!Enum.empty?(@recent_runs)} class="w-full text-sm">
          <thead>
            <tr class="text-left text-gray-400 border-b border-gray-700">
              <th class="pb-2 font-medium">Scenario</th>
              <th class="pb-2 font-medium">Score</th>
              <th class="pb-2 font-medium">Steps</th>
              <th class="pb-2 font-medium">Ranked</th>
              <th class="pb-2 font-medium">Date</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-800">
            <tr :for={run <- @recent_runs} class="hover:bg-gray-800 transition-colors">
              <td class="py-2 text-white font-medium"><%= run.scenario %></td>
              <td class="py-2 text-green-400 font-mono"><%= run.score %></td>
              <td class="py-2 text-gray-300"><%= run.steps %></td>
              <td class="py-2">
                <span :if={run.ranked} class="text-xs bg-indigo-800 text-indigo-200 px-2 py-0.5 rounded-full">ranked</span>
                <span :if={!run.ranked} class="text-xs text-gray-600">—</span>
              </td>
              <td class="py-2 text-gray-500"><%= Calendar.strftime(run.inserted_at, "%b %d, %Y") %></td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
