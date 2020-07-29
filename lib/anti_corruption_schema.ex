defmodule AntiCorruptionSchema do
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      @primary_key false

      def new(raw_map), do: unquote(__MODULE__).generic_new(raw_map, __MODULE__)
      def changeset(base, params), do: unquote(__MODULE__).generic_changeset(base, params)

      defoverridable new: 1, changeset: 2

      # NOTE you can override new/1 to perhaps call super and then do something more
      #      you can override changeset/2 to call super and then add validations
    end
  end

  def generic_new(raw_map, struct_module) do
    struct(struct_module)
    |> struct_module.changeset(raw_map)
    |> Ecto.Changeset.apply_action(:update)
  end

  def generic_changeset(base, raw_map) do
    struct_mod = base.__struct__
    embeds = struct_mod.__schema__(:embeds)
    allowed = struct_mod.__schema__(:fields) -- embeds

    chg = Ecto.Changeset.cast(base, raw_map, allowed)
    Enum.reduce(embeds, chg, &Ecto.Changeset.cast_embed(&2, &1))
  end
end
