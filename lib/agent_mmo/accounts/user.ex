defmodule AgentMmo.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Registration changeset — validates email + password and hashes the password.
  """
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_required([:email, :password])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email address")
    |> validate_length(:email, max: 160)
    |> validate_length(:password, min: 8, message: "must be at least 8 characters")
    |> unsafe_validate_unique(:email, AgentMmo.Repo)
    |> unique_constraint(:email)
    |> hash_password()
  end

  @doc """
  Login changeset — validates presence only; password verification is done separately.
  """
  def login_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_required([:email, :password])
  end

  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password -> put_change(changeset, :hashed_password, Bcrypt.hash_pwd_salt(password))
    end
  end

  @doc """
  Verify password against the stored hash.
  """
  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and is_binary(password) do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
