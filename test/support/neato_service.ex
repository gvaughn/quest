defmodule Quest.NeatoService do
  @default_q %Quest{
    dispatcher: Quest.HTTPoisonDispatcher,
    destiny: "neato",
    params: %{},
    base_url: "https://api.neato.com/v1/",
    adapter_options: [recv_timeout: 20000]
  }

  def client(%{service: "neato", api_token: token}, client_opts \\ []) do
    client_opts
    |> Keyword.merge(params: [source: token])
    |> Enum.into(@default_q)
  end

  def things(%Quest{} = q, params \\ []) do
    http_req(q, path: "things", params: params)
  end

  defp http_req(q, options) do
    options
    |> Enum.into(q)
    |> Quest.dispatch()
  end
end
