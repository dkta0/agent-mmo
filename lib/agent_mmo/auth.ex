defmodule AgentMmo.Auth do
  @moduledoc "API key issuance and verification with ETS caching."

  import Ecto.Query
  alias AgentMmo.{Repo, ApiKey}

  @cache_table :api_key_cache
  @cache_ttl_ms 60_000

  @doc "Initialize the ETS cache table. Safe to call multiple times."
  def init_cache do
    if :ets.whereis(@cache_table) == :undefined do
      :ets.new(@cache_table, [:named_table, :public, read_concurrency: true])
    end
    :ok
  end

  @doc """
  Issue a new API key.
  Returns {:ok, {plaintext_key, %ApiKey{}}} or {:error, changeset}.
  """
  def issue_key(%{"agent_name" => _, "owner" => _} = attrs) do
    raw = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    plaintext = "tb_" <> raw
    key_hash = hash_key(plaintext)
    key_prefix = String.slice(plaintext, 0, 5)

    changeset =
      ApiKey.changeset(%ApiKey{}, %{
        key_hash: key_hash,
        key_prefix: key_prefix,
        agent_name: attrs["agent_name"],
        owner: attrs["owner"]
      })

    case Repo.insert(changeset) do
      {:ok, api_key} -> {:ok, {plaintext, api_key}}
      {:error, cs} -> {:error, cs}
    end
  end

  def issue_key(_attrs) do
    changeset = ApiKey.changeset(%ApiKey{}, %{})
    {:error, changeset}
  end

  @doc """
  Verify a plaintext key. Returns {:ok, %ApiKey{}} | {:error, :invalid} | {:error, :revoked}.
  Caches results in ETS for 60s.
  """
  def verify_key(plaintext) when is_binary(plaintext) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@cache_table, plaintext) do
      [{^plaintext, result, expires_at}] when now < expires_at ->
        result

      _ ->
        result = db_verify(plaintext)
        :ets.insert(@cache_table, {plaintext, result, now + @cache_ttl_ms})
        result
    end
  end

  def verify_key(_), do: {:error, :invalid}

  defp db_verify(plaintext) do
    key_hash = hash_key(plaintext)

    case Repo.one(from k in ApiKey, where: k.key_hash == ^key_hash, limit: 1) do
      nil -> {:error, :invalid}
      %ApiKey{revoked_at: rev} when not is_nil(rev) -> {:error, :revoked}
      %ApiKey{} = api_key -> {:ok, api_key}
    end
  end

  defp hash_key(plaintext) do
    :crypto.hash(:sha256, plaintext) |> Base.encode16(case: :lower)
  end
end
