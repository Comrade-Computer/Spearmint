# Copyright (C) 2026 Aaron Schmidlkofer

defmodule Spearmint.StateTest do
  use ExUnit.Case, async: false
  doctest Spearmint.State

  defmodule TestStates do
    use Spearmint.State, states: [:a, :b, :c], default: :a
  end

  defmodule StateTransitionHistory do
    use Spearmint.Resource, state: [history: []]
  end

  defmodule StateTransitionHistorySystem do
    use Spearmint.System,
      lock_components: [],
      event_subscriptions: [Spearmint.Event.StateTransition]

    @spec run(Spearmint.Event.StateTransition.t(), Spearmint.Frame.t()) :: term()
    def run(%Spearmint.Event.StateTransition{} = event, _frame) do
      {:ok, history} = StateTransitionHistory.fetch()
      Spearmint.Command.update_resource!(history, history: [event | history.history])
    end
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
          :c -> :a
        end

      TestStates.set_state!(next_state)
    end
  end

  defmodule TestSpearmint do
    use Spearmint

    @spec setup(Spearmint.Data.t()) :: Spearmint.Data.t()
    def setup(data) do
      data
      |> Spearmint.init_state(TestStates)
      |> Spearmint.insert_resource(StateTransitionHistory)
      |> add_frame_end_system(StateTransitionHistorySystem)
      |> add_frame_end_system(StateRotationSystem)
    end
  end

  test "States transition circularly" do
    # These transitions do not appear to line up "correctly" with the events in the history.
    # This is because the state has to transition, generating the event
    # Then the next frame, the event is added to the history during event processing
    # AND the state transitions again. So the history is always a frame behind.

    # Setup a Simulation and process the first frame
    {:ok, pid} = Spearmint.Simulation.start_link(TestSpearmint, 0)
    Spearmint.System.debug(system_module: StateRotationSystem)
    Spearmint.Simulation.prepare()

    {:ok, state!} = TestStates.fetch()
    {:ok, history!} = StateTransitionHistory.fetch()
    assert :a == state!.current
    assert Enum.empty?(history!.history)

    Spearmint.Simulation.process_frame()
    {:ok, state!} = TestStates.fetch()
    {:ok, history!} = StateTransitionHistory.fetch()
    assert :b == state!.current
    assert Enum.empty?(history!.history)

    Spearmint.Simulation.process_frame()
    {:ok, state!} = TestStates.fetch()
    {:ok, history!} = StateTransitionHistory.fetch()
    assert :c == state!.current
    assert :a == (history!.history |> Enum.at(0)).previous_state
    assert :b == (history!.history |> Enum.at(0)).current_state

    Spearmint.Simulation.process_frame()
    {:ok, state!} = TestStates.fetch()
    {:ok, history!} = StateTransitionHistory.fetch()
    assert :a == state!.current
    assert :b == (history!.history |> Enum.at(0)).previous_state
    assert :c == (history!.history |> Enum.at(0)).current_state

    Spearmint.Simulation.process_frame()
    {:ok, state!} = TestStates.fetch()
    {:ok, history!} = StateTransitionHistory.fetch()
    assert :b == state!.current
    assert :c == (history!.history |> Enum.at(0)).previous_state
    assert :a == (history!.history |> Enum.at(0)).current_state

    Spearmint.Simulation.process_frame()
    {:ok, state!} = TestStates.fetch()
    {:ok, history!} = StateTransitionHistory.fetch()
    assert :c == state!.current
    assert :a == (history!.history |> Enum.at(0)).previous_state
    assert :b == (history!.history |> Enum.at(0)).current_state

    # Cleanup
    Spearmint.Simulation.stop()
    assert not Process.alive?(pid)
  end
end
