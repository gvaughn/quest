defmodule Quest.NeatoService do
  @default_q %Quest{
    dispatcher: Quest.HTTPoisonDispatcher,
    params: %{},
    base_url: "https://api.neato.com/v1/",
    adapter_options: [recv_timeout: 20000]
  }

  def client(%{service: "neato", api_token: token}, client_opts \\ []) do
    client_opts
    |> Keyword.merge(params: [source: token])
    |> Enum.into(@default_q)
  end

  def things(req, params \\ []) do
    http_req(req, path: "things", params: params)
  end

  defp http_req(req, options) do
    options
    |> Enum.into(req)
    |> Quest.dispatch()
  end
end
