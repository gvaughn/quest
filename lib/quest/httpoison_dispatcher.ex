if Code.ensure_loaded?(HTTPoison) && Code.ensure_loaded?(Jason) do
  defmodule Quest.HTTPoisonDispatcher do
    alias HTTPoison.Response

    def dispatch(%Quest{} = q) do
      url = URI.merge(q.base_url, q.path) |> URI.to_string()
      options = [{:params, q.params} | q.adapter_options]

      HTTPoison.request(q.verb, url, encode_payload(q), q.headers, options)
      |> handle_response()
    end

    defp encode_payload(%{encoding: :json, verb: verb, payload: payload})
         when verb in [:post, :put],
         do: Jason.encode!(payload)

    defp encode_payload(%{encoding: :urlencoded, payload: payload}) do
      payload
      |> Enum.map(fn {key, value} -> "#{key}=#{URI.encode_www_form(value)}" end)
      |> Enum.join("&")
    end

    defp encode_payload(_), do: ""

    # http 200 success cases
    defp handle_response({:ok, %Response{body: body, status_code: 200}})
         when body in ["", nil] do
      {:ok, %{}}
    end

    defp handle_response({:ok, %Response{body: body, status_code: 200} = resp}) do
      case Jason.decode(body) do
        {:ok, resp} -> {:ok, resp}
        {:error, _} -> {:error, {:json, resp}}
      end
    end

    # http 204 success cases
    defp handle_response({:ok, %Response{status_code: 204}}),
      do: {:ok, :no_content}

    # other http response code
    defp handle_response({:ok, %Response{status_code: scode, body: body}}) do
      body =
        case Jason.decode(body) do
          {:ok, json} ->
            json

          # return unprocessed body
          _ ->
            body
        end

      {:error, {scode, body}}
    end

    # httpoison error case
    defp handle_response({:error, %HTTPoison.Error{} = exp}) do
      {:error, {Exception.message(exp), exp}}
    end

    # fallback case
    defp handle_response({_, response}) do
      {:error, {:unknown, response}}
    end
  end
else
  defmodule Quest.HTTPoisonDispatcher do
    def dispatch(_), do: raise("httpoision and jason must be in the deps before use")
  end
end
