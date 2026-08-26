# Copyright (C) 2026 Aaron Schmidlkofer

defmodule SpearmintTest do
  use ExUnit.Case, async: false
  doctest Spearmint

  defmodule TestSpearmint do
    use Spearmint

    @spec setup(any()) :: any()
    def setup(data) do
      data
      |> add_frame_end_system(Spearmint.System.Timer)
    end
  end

  test "Initialize a server" do
    {:ok, pid} = Spearmint.Simulation.start_link(TestSpearmint, 0)

    %Spearmint.Simulation.Implementation{} = state = Spearmint.Simulation.get_state()
    assert Enum.empty?(state.shutdown_systems)

    Spearmint.Simulation.stop()

    assert not Process.alive?(pid)
  end

  test "Very simple server run some empty frames" do
    {:ok, pid} = Spearmint.Simulation.start_link(TestSpearmint, 0)
    Spearmint.Simulation.prepare()
    Spearmint.Simulation.process_frame()
    Spearmint.Simulation.process_frame()
    Spearmint.Simulation.process_frame()
    Spearmint.Simulation.stop()

    assert not Process.alive?(pid)
  end
end
