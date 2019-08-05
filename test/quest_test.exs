defmodule QuestTest do
  use ExUnit.Case, async: true
  doctest Quest

  test "accumulates headers" do
    q = %Quest{headers: [{"X-extra", "garden-gnome"}], destiny: "garden", dispatcher: :dummy}

    q =
      [headers: [{"X-extra", "rainbow-unicorn"}]]
      |> Enum.into(q)
      |> Quest.basic_auth("me", "secret")

    assert :proplists.get_value("Authorization", q.headers, nil) |> String.starts_with?("Basic")
    assert 2 = :proplists.get_all_values("X-extra", q.headers) |> length()
  end
end
