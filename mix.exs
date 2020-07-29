defmodule Quest.MixProject do
  use Mix.Project

  def project do
    [
      app: :quest,
      version: "0.1.0",
      elixir: "~> 1.8",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test),
    do: ["test/support" | elixirc_paths(:all)]

  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:httpoison, "~> 1.5", only: :test},
      {:jason, "~> 1.1"},
      {:ecto, "~> 3.4"}
    ]
  end
end
