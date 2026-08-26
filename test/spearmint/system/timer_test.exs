# Copyright (C) 2026 Aaron Schmidlkofer

defmodule Spearmint.System.TimerTest do
  use ExUnit.Case, async: false
  doctest Spearmint.System.Timer
end

defmodule OnceTimerTest do
  use ExUnit.Case, async: false

  defmodule TestTimerFinishedEvent do
    use Spearmint.Template.Event.Timer

    @type t :: %__MODULE__{}
  end

  defmodule TimerComponent do
    use Spearmint.Template.Component.Timer,
      state: [duration: 1, time: 1, event: TestTimerFinishedEvent, mode: :once]
  end

  defmodule ExpirationHistoryComponent do
    use Spearmint.Component, state: [history: []], tags: [:expiration_history]

    @type t :: %__MODULE__{}

    @spec get_history() :: ExpirationHistoryComponent.t()
    def get_history do
      Spearmint.Query.select({Spearmint.Entity}, with: [ExpirationHistoryComponent])
      |> Spearmint.Query.one()
      |> elem(0)
      |> Spearmint.Query.fetch_tagged_component([:expiration_history])
    end
  end

  defmodule TimerEntity do
    @spec new :: term()
    def new do
      {Spearmint.Entity,
       components: [
         TimerComponent,
         ExpirationHistoryComponent
       ]}
    end
  end

  defmodule SpawnTimerSystem do
    use Spearmint.System

    @impl Spearmint.System.WithoutEventSubscriptions
    def run(_frame) do
      %Spearmint.Entity{} = Spearmint.Command.spawn_entity!(TimerEntity.new())
    end
  end

  defmodule AccExpirationHistorySystem do
    use Spearmint.System,
      lock_components: [ExpirationHistoryComponent],
      event_subscriptions: [TestTimerFinishedEvent]

    @spec run(TestTimerFinishedEvent.t(), Spearmint.Frame.t()) :: term()
    def run(%TestTimerFinishedEvent{entity_id: entity_id} = event, _frame) do
      with {:ok, entity} <- Spearmint.Query.fetch_entity(entity_id),
           {:ok, history} <- Spearmint.Query.fetch_component(entity, ExpirationHistoryComponent) do
        Spearmint.Command.update_component!(history, history: [event | history.history])
      end
    end
  end

  defmodule TestSpearmint do
    use Spearmint

    @spec setup(Spearmint.Data.t()) :: Spearmint.Data.t()
    def setup(data) do
      data
      |> add_startup_system(SpawnTimerSystem)
      |> add_system(AccExpirationHistorySystem)
      |> add_frame_end_system(Spearmint.System.Timer)
    end
  end

  test "basic timer test" do
    # Setup a Simulation and process the first frame
    {:ok, pid} = Spearmint.Simulation.start_link(TestSpearmint, 0)
    Spearmint.Simulation.prepare()
    Spearmint.Simulation.process_frame()

    # After the 2nd frame is processed, the timer will go off.
    # Verify it has not fired early
    {:ok, history_component!} = ExpirationHistoryComponent.get_history()
    assert Enum.empty?(history_component!.history)

    # Process the second frame and ensure the timer went off once.
    Spearmint.Simulation.process_frame()
    {:ok, history_component!} = ExpirationHistoryComponent.get_history()
    assert 1 == Enum.count(history_component!.history)

    # Since the timer is not repeating, ensure it does not go off again.
    Spearmint.Simulation.process_frame()
    Spearmint.Simulation.process_frame()
    Spearmint.Simulation.process_frame()
    Spearmint.Simulation.process_frame()
    Spearmint.Simulation.process_frame()
    Spearmint.Simulation.process_frame()
    Spearmint.Simulation.process_frame()
    {:ok, history_component!} = ExpirationHistoryComponent.get_history()
    assert 1 == Enum.count(history_component!.history)

    # Cleanup
    Spearmint.Simulation.stop()
    assert not Process.alive?(pid)
  end
end

defmodule RepeatTimerTest do
  use ExUnit.Case, async: false

  defmodule TestTimerFinishedEvent do
    use Spearmint.Template.Event.Timer

    @type t :: %__MODULE__{}
  end

  defmodule TimerComponent do
    use Spearmint.Template.Component.Timer,
      state: [duration: 2, time: 1, event: TestTimerFinishedEvent, mode: :repeat]
  end

  defmodule ExpirationHistoryComponent do
    use Spearmint.Component, state: [history: []], tags: [:expiration_history]

    @type t :: %__MODULE__{}

    @spec get_history() :: ExpirationHistoryComponent.t()
    def get_history do
      Spearmint.Query.select({Spearmint.Entity}, with: [ExpirationHistoryComponent])
      |> Spearmint.Query.one()
      |> elem(0)
      |> Spearmint.Query.fetch_tagged_component([:expiration_history])
    end
  end

  defmodule TimerEntity do
    @spec new :: term()
    def new do
      {Spearmint.Entity,
       components: [
         TimerComponent,
         ExpirationHistoryComponent
       ]}
    end
  end

  defmodule SpawnTimerSystem do
    use Spearmint.System

    @impl Spearmint.System.WithoutEventSubscriptions
    def run(_frame) do
      %Spearmint.Entity{} = Spearmint.Command.spawn_entity!(TimerEntity.new())
    end
  end

  defmodule AccExpirationHistorySystem do
    use Spearmint.System,
      lock_components: [ExpirationHistoryComponent],
      event_subscriptions: [TestTimerFinishedEvent]

    @spec run(TestTimerFinishedEvent.t(), Spearmint.Frame.t()) :: term()
    def run(%TestTimerFinishedEvent{entity_id: entity_id} = event, _frame) do
      with {:ok, entity} <- Spearmint.Query.fetch_entity(entity_id),
           {:ok, history} <- Spearmint.Query.fetch_component(entity, ExpirationHistoryComponent) do
        Spearmint.Command.update_component!(history, history: [event | history.history])
      end
    end
  end

  defmodule TestSpearmint do
    use Spearmint

    @spec setup(Spearmint.Data.t()) :: Spearmint.Data.t()
    def setup(data) do
      data
      |> add_startup_system(SpawnTimerSystem)
      |> add_system(AccExpirationHistorySystem)
      |> add_frame_end_system(Spearmint.System.Timer)
    end
  end

  test "basic timer test" do
    # Setup a Simulation and process the first frame
    {:ok, pid} = Spearmint.Simulation.start_link(TestSpearmint, 0)
    Spearmint.Simulation.prepare()
    Spearmint.Simulation.process_frame()

    # After the 2nd frame is processed, the timer will go off.
    # Verify it has not fired early
    {:ok, history_component!} = ExpirationHistoryComponent.get_history()
    assert Enum.empty?(history_component!.history)

    # Process the second frame and ensure the timer went off once.
    Spearmint.Simulation.process_frame()
    {:ok, history_component!} = ExpirationHistoryComponent.get_history()
    assert 1 == Enum.count(history_component!.history)

    Spearmint.Simulation.process_frame()
    {:ok, history_component!} = ExpirationHistoryComponent.get_history()
    assert 1 == Enum.count(history_component!.history)

    Spearmint.Simulation.process_frame()
    {:ok, history_component!} = ExpirationHistoryComponent.get_history()
    assert 2 == Enum.count(history_component!.history)

    Spearmint.Simulation.process_frame()
    {:ok, history_component!} = ExpirationHistoryComponent.get_history()
    assert 2 == Enum.count(history_component!.history)

    Spearmint.Simulation.process_frame()
    {:ok, history_component!} = ExpirationHistoryComponent.get_history()
    assert 3 == Enum.count(history_component!.history)

    # Cleanup
    Spearmint.Simulation.stop()
    assert not Process.alive?(pid)
  end
end

defmodule TemporaryTimerTest do
  use ExUnit.Case, async: false

  defmodule TestTimerFinishedEvent do
    use Spearmint.Template.Event.Timer

    @type t :: %__MODULE__{}
  end

  defmodule TimerComponent do
    use Spearmint.Template.Component.Timer,
      state: [duration: 2, time: 2, event: TestTimerFinishedEvent, mode: :temporary]
  end

  defmodule ExpirationHistoryComponent do
    use Spearmint.Component, state: [history: []], tags: [:expiration_history]

    @type t :: %__MODULE__{}

    @spec get_history() :: ExpirationHistoryComponent.t()
    def get_history do
      Spearmint.Query.select({Spearmint.Entity}, with: [ExpirationHistoryComponent])
      |> Spearmint.Query.one()
      |> elem(0)
      |> Spearmint.Query.fetch_tagged_component([:expiration_history])
    end
  end

  defmodule TimerEntity do
    @spec new :: term()
    def new do
      {Spearmint.Entity,
       components: [
         TimerComponent,
         ExpirationHistoryComponent
       ]}
    end
  end

  defmodule SpawnTimerSystem do
    use Spearmint.System

    @impl Spearmint.System.WithoutEventSubscriptions
    def run(_frame) do
      %Spearmint.Entity{} = Spearmint.Command.spawn_entity!(TimerEntity.new())
    end
  end

  defmodule AccExpirationHistorySystem do
    use Spearmint.System,
      lock_components: [ExpirationHistoryComponent],
      event_subscriptions: [TestTimerFinishedEvent]

    @spec run(TestTimerFinishedEvent.t(), Spearmint.Frame.t()) :: term()
    def run(%TestTimerFinishedEvent{entity_id: entity_id} = event, _frame) do
      with {:ok, entity} <- Spearmint.Query.fetch_entity(entity_id),
           {:ok, history} <- Spearmint.Query.fetch_component(entity, ExpirationHistoryComponent) do
        Spearmint.Command.update_component!(history, history: [event | history.history])
      end
    end
  end

  defmodule TestSpearmint do
    use Spearmint

    @spec setup(Spearmint.Data.t()) :: Spearmint.Data.t()
    def setup(data) do
      data
      |> add_startup_system(SpawnTimerSystem)
      |> add_system(AccExpirationHistorySystem)
      |> add_frame_end_system(Spearmint.System.Timer)
    end
  end

  test "basic timer test" do
    # Setup a Simulation and process the first frame
    {:ok, pid} = Spearmint.Simulation.start_link(TestSpearmint, 0)
    Spearmint.Simulation.prepare()
    Spearmint.Simulation.process_frame()

    # After the 2nd frame is processed, the timer will go off.
    # Verify it has not fired early
    {:ok, history_component!} = ExpirationHistoryComponent.get_history()
    assert Enum.empty?(history_component!.history)

    # A timer should exist before the first timer has gone off
    assert Spearmint.Query.select({Spearmint.Entity}, with: [TimerComponent])
           |> Spearmint.Query.stream()
           |> Enum.empty?()
           |> Kernel.not()

    # Process the third frame and ensure the timer no longer exists.
    # The expiration will not appear in the history just yet since it is an event
    Spearmint.Simulation.process_frame()

    assert Spearmint.Query.select({Spearmint.Entity}, with: [TimerComponent])
           |> Spearmint.Query.stream()
           |> Enum.empty?()

    {:ok, history_component!} = ExpirationHistoryComponent.get_history()
    assert Enum.empty?(history_component!.history)

    # One more frame so the event will appear in the history
    Spearmint.Simulation.process_frame()
    {:ok, history_component!} = ExpirationHistoryComponent.get_history()
    assert 1 == Enum.count(history_component!.history)

    # Cleanup
    Spearmint.Simulation.stop()
    assert not Process.alive?(pid)
  end
end

defmodule TimerArgumentErrorTest do
  use ExUnit.Case, async: false

  defmodule TestTimerFinishedEvent do
    use Spearmint.Template.Event.Timer

    @type t :: %__MODULE__{}
  end

  defmodule TimerComponent do
    use Spearmint.Template.Component.Timer,
      state: [duration: 1, time: 1, event: TestTimerFinishedEvent, mode: :once]

    @impl Spearmint.Component
    def validate(data) do
      Spearmint.Template.Component.Timer.validate(data)
    end
  end

  defmodule HeroComponent do
    use Spearmint.Component, state: [name: "batman"]
  end

  defmodule HeroEntity do
    @spec new :: term()
    def new do
      {Spearmint.Entity,
       components: [
         HeroComponent,
         TimerComponent
       ]}
    end
  end

  defmodule SpawnHeroSystem do
    use Spearmint.System

    @impl Spearmint.System.WithoutEventSubscriptions
    def run(_frame) do
      Spearmint.Command.spawn_entity!(HeroEntity.new())
    end

    @spec fetch_hero() :: Spearmint.Entity.t()
    def fetch_hero do
      Spearmint.Query.select({Spearmint.Entity}, with: [HeroComponent])
      |> Spearmint.Query.one()
      |> elem(0)
    end
  end

  defmodule TestSpearmint do
    use Spearmint

    @spec setup(Spearmint.Data.t()) :: Spearmint.Data.t()
    def setup(data) do
      data
      |> add_startup_system(SpawnHeroSystem)
      |> add_frame_end_system(Spearmint.System.Timer)
    end
  end

  test "ArgumentErrorTests" do
    # Setup a Simulation and process the first frame
    {:ok, pid} = Spearmint.Simulation.start_link(TestSpearmint, 0)
    Spearmint.Simulation.prepare()

    Spearmint.System.debug(system_module: SpawnHeroSystem)
    hero = SpawnHeroSystem.fetch_hero()
    {:ok, old} = Spearmint.Query.fetch_component(hero, TimerComponent)
    Spearmint.Command.remove_component!(old)

    assert_raise ArgumentError, fn ->
      Spearmint.Command.add_component!(hero, {TimerComponent, [duration: "hoofygoofy"]})
    end

    assert_raise ArgumentError, fn ->
      Spearmint.Command.add_component!(hero, {TimerComponent, [time: "hoofygoofy"]})
    end

    assert_raise ArgumentError, fn ->
      Spearmint.Command.add_component!(hero, {TimerComponent, [event: "hoofygoofy"]})
    end

    assert_raise ArgumentError, fn ->
      Spearmint.Command.add_component!(hero, {TimerComponent, [mode: "hoofygoofy"]})
    end

    assert_raise ArgumentError, fn ->
      Spearmint.Command.add_component!(hero, {TimerComponent, [paused: "hoofygoofy"]})
    end

    # Cleanup
    Spearmint.Simulation.stop()
    assert not Process.alive?(pid)
  end
end
