# Forked from ECSpanse 0.10.1 https://github.com/iacobson/ecspanse/releases/tag/v0.10.1
# Modifications Copyright (C) 2026 Aaron Schmidlkofer

defmodule Spearmint.Projection.Supervisor do
  @moduledoc false
  # The projection supervisor spawns new temporary Projection servers.

  use DynamicSupervisor

  @spec child_spec(map()) :: map()
  def child_spec(%{name: name}) do
    %{
      id: name,
      start: {__MODULE__, :start_link, [name]},
      restart: :temporary,
      type: :supervisor
    }
  end

  # API

  @spec start_link() :: {:error, any()} | {:ok, pid()}
  def start_link do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  # SERVER

  @impl DynamicSupervisor
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
