defmodule AgentMmo.Repo.Migrations.FixRunsTimestamps do
  use Ecto.Migration

  def change do
    # The original migration created inserted_at NOT NULL (from timestamps/0).
    # The Run schema uses timestamps(inserted_at: :completed_at) so Ecto writes
    # to completed_at, not inserted_at. Set a default so old insertions don't fail.
    execute(
      "ALTER TABLE runs ALTER COLUMN inserted_at SET DEFAULT now()",
      "ALTER TABLE runs ALTER COLUMN inserted_at DROP DEFAULT"
    )
  end
end
