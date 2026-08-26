# Forked from ECSpanse 0.10.1 https://github.com/iacobson/ecspanse/releases/tag/v0.10.1
# Modifications Copyright (C) 2026 Aaron Schmidlkofer

defmodule Spearmint.Simulation.Server do
  @moduledoc """
  A GenServer that contains the state and can be used to control a simulation instance
  """
  use GenServer
  alias Spearmint.Simulation.Implementation

  @impl GenServer
  def init({ecspanse_module, ecs_version}) do
    {:ok, Implementation.new(ecspanse_module, ecs_version)}
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:prepare, _from, state) do
    {:reply, :ok, Implementation.prepare(state)}
  end

  def handle_call(:process_frame, _from, state) do
    {:reply, :ok, Implementation.process_frame(state)}
  end

  def handle_call(:run_shutdown_systems, _from, state) do
    {:reply, :ok, Implementation.run_shutdown_systems(state)}
  end
end
