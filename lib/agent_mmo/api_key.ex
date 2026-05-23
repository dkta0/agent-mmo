defmodule AgentMmo.ApiKey do
  use Ecto.Schema
  import Ecto.Changeset

  schema "api_keys" do
    field :key_hash,   :string
    field :key_prefix, :string
    field :agent_name, :string
    field :owner,      :string
    field :revoked_at, :utc_datetime

    belongs_to :user, AgentMmo.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [:key_hash, :key_prefix, :agent_name, :owner, :user_id])
    |> validate_required([:key_hash, :key_prefix, :agent_name, :owner])
    |> validate_length(:agent_name, min: 3, max: 128)
    |> validate_format(:agent_name, ~r/^[a-zA-Z0-9_-]+$/,
        message: "only alphanumeric, hyphens, underscores allowed")
    |> validate_length(:owner, min: 1, max: 256)
    |> unique_constraint(:key_hash)
  end
end
