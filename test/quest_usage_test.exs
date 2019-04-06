defmodule QuestUsageTest do
  use ExUnit.Case, async: true
  alias Quest.NeatoService

  @client_creds %{service: "neato", api_token: "test_token"}

  test "can supply canned response" do
    mocked_dispatcher = fn %Quest{params: %{type: "shirts", source: token}} ->
      assert token == "test_token"
      {:ok, %{"things" => [%{"title" => "Pockets on a Shirt!"}]}}
    end

    {:ok, resp} =
      NeatoService.client(@client_creds, dispatcher: mocked_dispatcher)
      |> NeatoService.things(type: "shirts")

    first_thing = get_in(resp, ["things", Access.at(0)])

    assert %{"title" => "Pockets on a Shirt!"} = first_thing
  end
end
