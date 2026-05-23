defmodule AgentMmo.Run do
  use Ecto.Schema
  import Ecto.Changeset

  schema "runs" do
    field :scenario, :string
    field :score, :integer
    field :ranked, :boolean, default: false
    field :completed_at, :utc_datetime

    belongs_to :user, AgentMmo.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:user_id, :scenario, :score, :ranked, :completed_at])
    |> validate_required([:scenario, :score])
    |> validate_length(:scenario, min: 1, max: 256)
    |> validate_number(:score, greater_than_or_equal_to: 0)
  end
end
