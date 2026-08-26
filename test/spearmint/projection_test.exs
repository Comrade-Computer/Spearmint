# Copyright (C) 2026 Aaron Schmidlkofer

defmodule Spearmint.ProjectionTest do
  use ExUnit.Case, async: false
  doctest Spearmint.Projection

  defmodule TestStates do
    use Spearmint.State, states: [:a, :b, :c, :d, :e, :f, :g], default: :a
  end

  defmodule StateTransitionHistory do
    use Spearmint.Resource, state: [history: []]
  end

  defmodule StateRotationSystem do
    use Spearmint.System, lock_components: [], event_subscriptions: []

    @impl Spearmint.System.WithoutEventSubscriptions
    def run(_frame) do
      {:ok, state} = TestStates.fetch()

      next_state =
        case state.current do
          :a -> :b
          :b -> :c
          :c -> :d
          :d -> :e
          :e -> :f
          :f -> :g
          :g -> :a
        end

      TestStates.set_state!(next_state)
    end
  end

  defmodule TestProjection do
    use Spearmint.Projection, fields: [:state]

    @impl Spearmint.Projection
    def project(_attrs) do
      {:ok, state} = TestStates.fetch()

      case state.current do
        :a -> :loading
        :b -> {:loading, :b}
        :c -> {:ok, %TestProjection{state: :c}}
        :d -> {:ok, %TestProjection{state: :d}}
        :e -> {:error, %TestProjection{state: :e}}
        :f -> :error
        :g -> :halt
      end
    end

    @impl Spearmint.Projection
    def on_change(%{client_pid: pid}, projection, previous_projection) do
      GenServer.call(pid, {:acc, {projection, previous_projection}})
    end
  end

  defmodule Accumulator do
    use GenServer

    @impl GenServer
    def init(_args) do
      {:ok, []}
    end

    @impl GenServer
    def handle_call(:get, _from, state) do
      {:reply, state, state}
    end

    def handle_call({:acc, val}, _from, state) do
      {:reply, :ok, [val | state]}
    end
  end

  defmodule TestSpearmint do
    use Spearmint

    @spec setup(Spearmint.Data.t()) :: Spearmint.Data.t()
    def setup(data) do
      data
      |> Spearmint.init_state(TestStates)
      |> add_frame_end_system(StateRotationSystem)
    end
  end

  test "States transition circularly" do
    # These transitions do not appear to line up "correctly" with the events in the history.
    # This is because the state has to transition, generating the event
    # Then the next frame, the event is added to the history during event processing
    # AND the state transitions again. So the history is always a frame behind.

    {:ok, acc_pid} = GenServer.start_link(Accumulator, nil)
    assert GenServer.call(acc_pid, :get) |> Enum.empty?()

    # Setup a Simulation and process the first frame
    {:ok, pid} = Spearmint.Simulation.start_link(TestSpearmint, 0)
    Spearmint.System.debug(system_module: StateRotationSystem)
    Spearmint.Simulation.prepare()

    projection_pid = TestProjection.start!(%{client_pid: acc_pid})
    assert 1 == GenServer.call(acc_pid, :get) |> Enum.count()
    projection! = TestProjection.get!(projection_pid)

    assert projection! == %Spearmint.Projection{
             state: :loading,
             result: nil,
             loading?: true,
             ok?: false,
             error?: false,
             halted?: false
           }

    Spearmint.Simulation.process_frame()
    assert 2 == GenServer.call(acc_pid, :get) |> Enum.count()
    projection! = TestProjection.get!(projection_pid)

    assert projection! == %Spearmint.Projection{
             state: :loading,
             result: :b,
             loading?: true,
             ok?: false,
             error?: false,
             halted?: false
           }

    Spearmint.Simulation.process_frame()
    assert 3 == GenServer.call(acc_pid, :get) |> Enum.count()
    projection! = TestProjection.get!(projection_pid)

    assert projection! == %Spearmint.Projection{
             state: :ok,
             result: %TestProjection{state: :c},
             loading?: false,
             ok?: true,
             error?: false,
             halted?: false
           }

    Spearmint.Simulation.process_frame()
    assert 4 == GenServer.call(acc_pid, :get) |> Enum.count()
    projection! = TestProjection.get!(projection_pid)

    assert projection! == %Spearmint.Projection{
             state: :ok,
             result: %TestProjection{state: :d},
             loading?: false,
             ok?: true,
             error?: false,
             halted?: false
           }

    Spearmint.Simulation.process_frame()
    assert 5 == GenServer.call(acc_pid, :get) |> Enum.count()
    projection! = TestProjection.get!(projection_pid)

    assert projection! == %Spearmint.Projection{
             state: :error,
             result: %TestProjection{state: :e},
             loading?: false,
             ok?: false,
             error?: true,
             halted?: false
           }

    Spearmint.Simulation.process_frame()
    assert 6 == GenServer.call(acc_pid, :get) |> Enum.count()
    projection! = TestProjection.get!(projection_pid)

    assert projection! == %Spearmint.Projection{
             state: :error,
             result: nil,
             loading?: false,
             ok?: false,
             error?: true,
             halted?: false
           }

    Spearmint.Simulation.process_frame()
    assert 7 == GenServer.call(acc_pid, :get) |> Enum.count()
    projection! = TestProjection.get!(projection_pid)

    assert projection! == %Spearmint.Projection{
             state: :halt,
             result: nil,
             loading?: false,
             ok?: false,
             error?: false,
             halted?: true
           }

    # Cleanup
    Spearmint.Simulation.stop()
    assert not Process.alive?(pid)

    GenServer.stop(acc_pid)
    assert not Process.alive?(acc_pid)
  end
end
