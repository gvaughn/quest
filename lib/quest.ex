defmodule Quest do
  require Logger

  @moduledoc """
  This struct represents an outgoing HTTP call in the abstract sense.
  It can be built up in pieces, then dispatched via:
  `Quest.dispatch(quest_struct)`
  """

  @enforce_keys [:dispatcher, :destiny]
  # We can't enforce :base_url because it might be set after initial creation
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
            dispatcher: nil,
            destiny: nil

  @doc """
  Execute/dispatch the Quest struct
  It uses the `dispatcher` field.
    if it is an arity one anonymous function, it calls it passing the Quest to it
    if it is an atom, it expects it to be a Module with a `dispatch/1` function
  """
  def dispatch(%__MODULE__{dispatcher: dispatcher} = q) do
    verbose = is_verbose?(q)

    if verbose do
      Logger.info(inspect(q, pretty: true))
      Logger.info(debug_string(q))
    end

    resp =
      case dispatcher do
        nil -> raise("Must set `dispatcher` field")
        fun when is_function(fun, 1) -> fun.(q)
        mod when is_atom(mod) -> dispatcher.dispatch(q)
      end

    if verbose, do: Logger.info(inspect(resp, pretty: true))
    resp
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

  # description_or_list is a single destiny (string) or a list of them
  def set_verbose(description_or_list \\ [:all]) do
    Application.put_env(:quest, :verbose_destinies, List.wrap(description_or_list))
  end

  def unset_verbose(description_or_list \\ [:all]) do
    # NOTE there's an odd corner case. If currently set to [:all] this
    # will unset all no matter what description_or_list contains
    # because we can't enumerate all values of Quest.destiny
    new_list =
      case {description_or_list, Application.get_env(:quest, :verbose_destinies) || []} do
        {[:all], _} -> []
        {_, [:all]} -> []
        {to_remove, current} -> current -- List.wrap(to_remove)
      end

    Application.put_env(:quest, :verbose_destinies, new_list)
  end

  defp is_verbose?(%__MODULE__{debug: debug, destiny: desc}) do
    verbose_destinies = Application.get_env(:quest, :verbose_destinies) || []
    debug || verbose_destinies == [:all] || desc in verbose_destinies
  end

  def debug_string(q) do
    verb_part = q.verb |> to_string() |> String.upcase()
    uri = URI.merge(q.url, q.path)

    uri =
      if Enum.any?(q.params) do
        %{uri | query: URI.encode_query(q.params)}
      else
        uri
      end

    body_part =
      if q.verb in [:post, :put, :patch] && q.encoding == :json do
        " | Body: #{Jason.encode!(q.payload)}"
      else
        " | Body: #{inspect(q.payload)}"
      end

    header_part =
      if Enum.any?(q.headers) do
        " | Headers: #{inspect(q.headers)}"
      else
        ""
      end

    Enum.join([verb_part, " ", uri, body_part, header_part])
  end

  defimpl Collectable do
    @collectable_struct_members [:params, :headers, :adapter_options, :appmeta]
    @replaceable_struct_members %Quest{
                                  dispatcher: :dummy,
                                  destiny: :dummy
                                }
                                |> Map.keys()
                                |> Kernel.--(@collectable_struct_members)
                                |> Kernel.--([:__struct__])

    def into(req) do
      {req, &collector/2}
    end

    defp collector(%{base_url: nil} = req, {:cont, {:base_url, _value} = update}) do
      struct!(req, [update])
    end

    # Special case: We break base_url down to set params by query string and figure out path
    # Useful for HAL-style links. Set the base_url to the embedded link and the Request is
    # ready to run
    defp collector(req, {:cont, {:base_url, value}}) do
      u = URI.parse(value)

      params =
        if q = u.query do
          url_params =
            String.split(q, ["&", "="]) |> Enum.chunk_every(2) |> Enum.map(&List.to_tuple/1)

          update_collectable(req.params, url_params)
        else
          req.params
        end

      # See if old req.base_url is a prefix of new url via String.split
      {new_url, new_path} =
        case %URI{u | query: nil} |> URI.to_string() |> String.split(req.base_url) do
          ["", path] -> {req.base_url, path}
          [url] -> {url, ""}
        end

      struct!(req, params: params, base_url: new_url, path: new_path)
    end

    defp collector(req, {:cont, {key, value}}) when key in @collectable_struct_members do
      Map.replace!(req, key, update_collectable(Map.get(req, key), value))
    end

    defp collector(req, {:cont, {key, _value} = update})
         when key in @replaceable_struct_members do
      struct!(req, [update])
    end

    # ignore unknown keys
    defp collector(req, {:cont, _}) do
      req
    end

    defp collector(req, :done), do: req
    defp collector(_req, :halt), do: :ok

    defp update_collectable(current_value, new_value) when is_map(current_value) do
      Enum.into(new_value, current_value)
    end

    defp update_collectable(current_value, new_value) when is_list(current_value) do
      Enum.to_list(new_value) ++ current_value
    end
  end
end
