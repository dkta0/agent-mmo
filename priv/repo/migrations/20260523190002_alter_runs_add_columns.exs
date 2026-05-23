defmodule AgentMmo.Repo.Migrations.AlterRunsAddColumns do
  use Ecto.Migration

  def change do
    alter table(:runs) do
      add_if_not_exists :api_key_id,  references(:api_keys, on_delete: :nilify_all), null: true
      add_if_not_exists :steps,       :integer, null: false, default: 0
      add_if_not_exists :duration_ms, :integer, null: false, default: 0
      add_if_not_exists :seed,        :string
      add_if_not_exists :replay_data, :map
    end

    # Remove columns from original migration that conflict with Run schema
    # (inserted_at / updated_at from timestamps() don't match the schema's
    # timestamps(updated_at: false, inserted_at: :completed_at) — those are already correct)

    # Drop updated_at if it exists (schema uses inserted_at: :completed_at, no updated_at)
    execute(
      "ALTER TABLE runs DROP COLUMN IF EXISTS updated_at",
      "ALTER TABLE runs ADD COLUMN IF NOT EXISTS updated_at timestamp(0) without time zone"
    )

    create_if_not_exists index(:runs, [:user_id, :scenario, :ranked])
  end
end
