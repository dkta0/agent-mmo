defmodule AgentMmo.Repo.Migrations.FixRunsTimestamps do
  use Ecto.Migration

  def change do
    # The runs table was created with inserted_at: :completed_at so there is no
    # `inserted_at` column — only `completed_at`. This migration is a no-op
    # retained only to keep the schema_migrations version consistent.
    :ok
  end
end
