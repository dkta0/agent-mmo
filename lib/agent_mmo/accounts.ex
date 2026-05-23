defmodule AgentMmo.Accounts do
  @moduledoc "User account management context."

  alias AgentMmo.Repo
  alias AgentMmo.Accounts.{User, UserToken}

  ## User registration and retrieval

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def get_user(id), do: Repo.get(User, id)

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)
    if User.valid_password?(user, password), do: user
  end

  ## Legacy authenticate_user/2 kept for backward compat
  def authenticate_user(email, password) do
    case get_user_by_email_and_password(email, password) do
      nil -> {:error, :invalid_credentials}
      user -> {:ok, user}
    end
  end

  ## Session tokens

  @doc "Generates a session token and persists it. Returns the raw binary token."
  def create_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc "Looks up a user by a session token. Returns the user or nil."
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc "Deletes a session token."
  def delete_session_token(token) do
    Repo.delete_all(UserToken.token_and_context_query(token, "session"))
    :ok
  end

  @doc "Deletes all tokens for the given user in the given contexts."
  def delete_user_session_tokens(user) do
    Repo.delete_all(UserToken.user_and_contexts_query(user, ["session"]))
  end

  ## Registration changeset helper

  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs)
  end

  def change_user_login(%User{} = user, attrs \\ %{}) do
    User.login_changeset(user, attrs)
  end
end
