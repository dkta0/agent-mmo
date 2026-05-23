defmodule AgentMmo.Repo.Migrations.AddUsersCitextAndTokens do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", "SELECT 1"

    alter table(:users) do
      add :confirmed_at, :utc_datetime
    end

    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false, size: 40
      add :sent_to, :string, size: 255

      timestamps(updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
