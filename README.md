# Quest

A `Quest` is like a re-quest with the goal of getting it right the first time!

This is a pattern I've extracted from production code for making API calls to third
party services. I'm not sure yet whether it will become a useful library itself, or
just an example of a pattern.

## Background

My original impetus was to achieve greater parallelism in our test suite.
Previously we had a global mock for 3rd party calls and had to serialize all
tests that called any particular service. With the Quest approach, we can keep ExUnit in
`async: true` mode.

I took inspiration from other libraries in the Elixir ecosystem, specifically the
`Plug.Conn` and `Ecto.Changeset`. Both are structs that we update in steps according
to our business logic, then at the end, conceptually "execute" them. It is related to
`Enum.reduce` over an accumulator, and in some circles the functions that perform
the updates are known as 'reducers'. Rene Föhring gave a [talk](https://www.youtube.com/watch?v=ycpNi701aCs&t=1s) at ElixirConf US 2018
calling the structs "tokens".

## Accumulation Pattern

"Accumulation Pattern" is the name I'm going with now, but let's see how the
community responds. I've augmented it by making the accumulator struct
implement `Collectable`.

## Quest Struct

```elixir
defmodule Quest do
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

  def dispatch(%__MODULE__{dispatcher: dispatcher} = q) do
    # more discussion below
  end
end
```

Most of the fields should be no surprise as a way of abstracting outgoing HTTP calls.
`debug` is a convenience to be more verbose in logging. `adapter_options` are intended
to abstract over options to send to the lower-level library that actually performs the
http calls. In my case, I've been using this with HTTPoison. `appmeta` is a catch-all
sort of field that lets us put app-specific metadata in there that other modules in
our codebase can use. Some examples are a metric name or login credentials/tokens or
a token to check for outgoing throttling, or a count of times to retry.

Note that `params`, `headers`, `adapter_options`, `appmeta` are all empty lists to allow for
proplists since duplicate keys may be required. In any particular use for a concrete
client implementation, they can be overridden with maps for convenience.

We'll come back to the `dispatcher` field and `dispatch/1` function after more of a
tour.

```elixir
defimpl Collectable, for: Quest do
  @collectable_struct_members [:params, :headers, :adapter_options, :appmeta]

  def into(q) do
    {q, &collector/2}
  end

  defp collector(q, {:cont, {key, value}}) when key in @collectable_struct_members do
    updated_value =
      case Map.get(q, key) do
        current_value when is_map(current_value) -> Enum.into(value, current_value)
        current_value when is_list(current_value) -> value ++ current_value
      end
    Map.replace!(q, key, updated_value)
  end

  defp collector(q, {:cont, {key, value}}) do
    Map.replace!(q, key, value)
  end

  defp collector(q, :done), do: q
  defp collector(_q, :halt), do: :ok
end
```

The `Collectable` protocol may not be that widely known, but it is what is required of
the 2nd parameter to `Enum.into/2`. This implementation does a 1-level merge. If the
key is among `params`, `headers`, `adapter_options`, `appmeta` then we merge into what
is already in the struct. Other fields are replaced. The advantage of this will become
more clear in our next code example of an API client module that makes use of this pattern.

```elixir
defmodule NeatoService do
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
```

First, notice that at compile time we create a default `Quest` struct with some additional
customization. We specify a module as the `dispatcher`, we limit `params` to be a map, we
specify a `base_url` (which could be read from `Application.get_env/2`) at compile time,
and we set some lower-level `adapter_options` because perhaps this service is known to be
slow and we need to increase the receive timeout.

The `client/1,2` call is expected to come first. It receives an `api_token` and pattern
matches to ensure it is for the right name of service. The `client_opts` are optional. We'll
come back to that. For this hypothetical NeatoService, it takes a `token` parameter. I've
used much more sophisticated styles of authentication with this pattern, but this is a good
first example.

Code that uses `NeatoService` would be expected to look something like:

```elixir
credentials = %{service: "neato", api_token: "bigsecret"}
client = NeatoService.client(credentials)
response = NeatoService.things(client, type: "uber_neato")
```

## Testing Story

Now the big reveal: that 2nd optional parameter to `NeatoService` is the key to enabling
asynchronous tests without a mock library. The `Quest.dispatch/1` function looks like this:

```elixir
  def dispatch(%__MODULE__{dispatcher: dispatcher} = q) do
    case dispatcher do
      fun when is_function(fun, 1) -> fun.(q)
      mod when is_atom(mod) -> dispatcher.dispatch(q)
    end
  end
```

That means your asynchronous, parallel tests can do this:

```elixir
test "neato shirt things" do
  mocked_dispatcher = fn %Quest{params: %{type: "shirts"}} ->
    {:ok, %{"things" => [%{"title"  => "Pockets on a Shirt!"}]}}
  end

  {:ok, resp} =
    %{service: "neato", api_token: "test_token"}
    |> NeatoService.client(dispatcher: mocked_dispatcher)
    |> NeatoService.things(type: "shirts")

  first_thing = get_in(resp, ["things", Access.at(0)])

  assert %{"title" => "Pockets on a Shirt!"} = first_thing
end
```

By supplying the `dispatcher` in that optional 2nd parameter to
`NeatoService.client` you can provide canned responses. That
`mocked_dispatcher` could even do its own assertions if it makes sense. The
overidden value of `dispatcher`, `HTTPoisonDispatcher` is rather
pedestrian, but can be found [here](https://github.com/gvaughn/quest/blob/master/lib/quest/httpoison_dispatcher.ex). Each test will have its own instance
of the `Quest` struct, which will each contain their own anonymous function
overriding the `dispatcher` field, and can therfore be run in parallel.

The `dispatcher` can also be something more app-specific. It might be a wrapper around
`Tesla`. Maybe you prefer `gun`. Or maybe you want to `mint` your lower level interactions.
It might log/send metrics/throttle outgoing calls. The choice is up to you. The
core idea is that you could make assertions against building up a proper `Quest` struct
as well as providing canned, asychronous-friendly responses in your tests. Using this
10+ times, my co-workers and I have found this a clear way to quickly build new, flexible,
API clients, and to keep our tests running efficiently.

## The Con

In normal production code use, you'll have an extra call to `NeatoService.client/1`
before a second call that really dispatches the Quest.
That client can be reused or cached in most cases when you have multiple calls to make
to the same service. I find it to be a worthwhile tradeoff for the testing
advantages it gains us.

## Further Possibilities

Once we adopt this Quest struct, there's more that can be done. I've created a
concept I call a `Gateway` that wraps the dispatcher to provide consistent
logging, metrics, outgoing throttling, and retry logic. I've also begun extracting
for reuse an `Unpager` module that can take API calls that have paged results and
wrap them in a `Stream` for the rest of my business logic to easily consume. Reuse
of these are made possible because they can rely on the common `Quest` struct as
a data structure that represents an action.

Love it? Hate it? Other? I'd appreciate your feedback via email or Twitter (@gregvaughn)

*Special thanks to my employer [Seat Scouts](http://seatscouts.com) for allowing
me to extract and share these examples, and for my co-workers who have experimented
with them with me.*
