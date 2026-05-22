defmodule AgentMmoWeb.KeyController do
  use AgentMmoWeb, :controller

  alias AgentMmo.Auth

  def create(conn, params) do
    case Auth.issue_key(params) do
      {:ok, {plaintext, api_key}} ->
        conn
        |> put_status(201)
        |> json(%{
          api_key: plaintext,
          key_prefix: api_key.key_prefix,
          agent_name: api_key.agent_name,
          owner: api_key.owner,
          created_at: api_key.inserted_at |> DateTime.to_iso8601()
        })

      {:error, changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Enum.reduce(opts, msg, fn {key, val}, acc ->
              String.replace(acc, "%{#{key}}", to_string(val))
            end)
          end)

        conn
        |> put_status(422)
        |> json(%{errors: errors})
    end
  end
end
