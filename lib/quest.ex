defmodule Quest do
  @moduledoc """
  This struct represents an outgoing HTTP call in the abstract sense.
  It can be built up in pieces, then dispatched via:
  `Quest.dispatch(quest_struct)`
  """

  defstruct verb: :get,
            base_url: nil,
            headers: [],
            path: "",
            params: [],
            payload: "",
            encoding: :json,
            debug: false,
            adapter_options: [],
            appmeta: [],
            dispatcher: nil

  @doc """
  Execute/dispatch the Quest struct
  It uses the `dispatcher` field.
    if it is an arity one anonymous function, it calls it passing the Quest to it
    if it is an atom, it expects it to be a Module with a `dispatch/1` function
  """
  def dispatch(%__MODULE__{dispatcher: dispatcher} = q) do
    case dispatcher do
      nil -> raise("Must set `dispatcher` field")
      fun when is_function(fun, 1) -> fun.(q)
      mod when is_atom(mod) -> dispatcher.dispatch(q)
    end
  end

  @doc """
  Inserts a basic auth header
  Note: this could be done by literally updating the `headers` field, but
  generic helper functions can also be added.
  """
  def basic_auth(%__MODULE__{} = q, username, password) do
    basic_auth = Base.encode64("#{username}:#{password}")
    Enum.into([headers: [{"Authorization", "Basic #{basic_auth}"}]], q)
  end
end

defimpl Collectable, for: Quest do
  @collectable_struct_members [:params, :headers, :adapter_options, :appmeta]

  def into(q) do
    {q, &collector/2}
  end

  defp collector(q, {:cont, {key, value}}) when key in @collectable_struct_members do
    updated_value =
      case Map.get(q, key) do
        current_value when is_map(current_value) -> Enum.into(value, current_value)
        current_value when is_list(current_value) -> Enum.to_list(value) ++ current_value
      end

    Map.replace!(q, key, updated_value)
  end

  defp collector(q, {:cont, {key, value}}) do
    Map.replace!(q, key, value)
  end

  defp collector(q, :done), do: q
  defp collector(_q, :halt), do: :ok
end
