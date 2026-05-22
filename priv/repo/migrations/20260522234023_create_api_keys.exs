defmodule AgentMmo.Repo.Migrations.CreateApiKeys do
  use Ecto.Migration

  def change do
    create table(:api_keys) do
      add :key_hash,   :string,  size: 64,  null: false
      add :key_prefix, :string,  size: 5,   null: false
      add :agent_name, :string,  size: 128, null: false
      add :owner,      :string,  size: 256, null: false
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:api_keys, [:key_hash])
    create index(:api_keys, [:key_hash], where: "revoked_at IS NULL", name: :api_keys_active_hash_idx)
  end
end
