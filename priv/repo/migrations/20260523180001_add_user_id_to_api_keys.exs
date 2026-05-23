defmodule AgentMmo.Repo.Migrations.AddUserIdToApiKeys do
  use Ecto.Migration

  def change do
    alter table(:api_keys) do
      add :user_id, references(:users, on_delete: :nilify_all), null: true
    end

    create index(:api_keys, [:user_id])
  end
end
