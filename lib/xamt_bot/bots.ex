defmodule XamtBot.Bots do
  @moduledoc """
  Local bot instance registry. Xamt remains the source of truth for identity
  and authorization; this context only stores runtime configuration.
  """

  import Ecto.Query
  alias XamtBot.Repo
  alias XamtBot.Bots.BotInstance

  def get_instance!(id), do: Repo.get!(BotInstance, id)

  def get_instance_by_external_id(external_bot_id) when is_binary(external_bot_id) do
    Repo.get_by(BotInstance, external_bot_id: external_bot_id)
  end

  def list_instances(opts \\ []) do
    status = Keyword.get(opts, :status)

    BotInstance
    |> maybe_filter_status(status)
    |> order_by([b], asc: b.name)
    |> Repo.all()
  end

  def create_instance(attrs) do
    %BotInstance{}
    |> BotInstance.changeset(attrs)
    |> Repo.insert()
  end

  def update_instance(%BotInstance{} = instance, attrs) do
    instance
    |> BotInstance.changeset(attrs)
    |> Repo.update()
  end

  def upsert_instance(attrs) do
    attrs = stringify_keys(attrs)

    %BotInstance{}
    |> BotInstance.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [:name, :handler_key, :status, :config, :signing_secret, :api_token, :updated_at]},
      conflict_target: :external_bot_id,
      returning: true
    )
  end

  def active?(%BotInstance{status: "active"}), do: true
  def active?(_), do: false

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: from(b in query, where: b.status == ^status)

  defp stringify_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
