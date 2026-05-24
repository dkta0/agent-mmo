defmodule AgentMmoWeb.ScenarioController do
  use AgentMmoWeb, :controller

  @moduledoc """
  REST shim for the MCP server.

  `GET /api/scenarios` — list playable scenarios from `priv/scenarios/*.yaml`.
  See `docs/issues/mcp-rest-protocol-mismatch.md` for the design context.
  """

  def index(conn, _params) do
    json(conn, scenarios())
  end

  defp scenarios do
    scenario_dir()
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".yaml"))
    |> Enum.map(&load_scenario/1)
  end

  defp scenario_dir, do: Application.app_dir(:agent_mmo, "priv/scenarios")

  defp load_scenario(filename) do
    path = Path.join(scenario_dir(), filename)
    contents = File.read!(path)

    %{
      id: read_field(contents, "id") || Path.rootname(filename),
      name: read_field(contents, "name") || filename,
      description: read_field(contents, "description") || "",
      difficulty: read_field(contents, "difficulty") || "medium"
    }
  end

  # Minimal YAML scalar reader for the fields we expose. The scenarios YAML
  # files use simple `key: "value"` lines at the top level, so a regex avoids
  # pulling in a YAML dep for this one read path.
  defp read_field(contents, key) do
    pattern = ~r/^#{Regex.escape(key)}:\s*"?(?<value>[^"\n]+)"?\s*$/m

    case Regex.named_captures(pattern, contents) do
      %{"value" => value} -> String.trim(value)
      _ -> nil
    end
  end
end
