# Forked from ECSpanse 0.10.1 https://github.com/iacobson/ecspanse/releases/tag/v0.10.1
# Modifications Copyright (C) 2026 Aaron Schmidlkofer

defmodule Spearmint.Simulation do
  @moduledoc """
  The public API for starting and using Spearmint Simulations
  """
  alias Spearmint.Simulation.Implementation
  alias Spearmint.Simulation.Server

  @spec start_link(atom(), non_neg_integer()) :: {:error, any()} | {:ok, pid()}
  def start_link(ecspanse_module, ecs_version) do
    GenServer.start_link(Server, {ecspanse_module, ecs_version}, name: MyServer)
  end

  @spec get_state() :: Implementation.t()
  def get_state do
    GenServer.call(MyServer, :get_state)
  end

  @spec stop() :: any()
  def stop() do
    GenServer.call(MyServer, :run_shutdown_systems)
    GenServer.stop(MyServer)
  end

  @spec prepare() :: any()
  def prepare() do
    GenServer.call(MyServer, :prepare)
  end

  @spec process_frame() :: any()
  def process_frame() do
    GenServer.call(MyServer, :process_frame)
  end
end
