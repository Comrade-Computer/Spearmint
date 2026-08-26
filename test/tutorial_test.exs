# Copyright (C) 2026 Aaron Schmidlkofer

defmodule TutorialTest do
  defmodule Demo do
    use ExUnit.Case, async: false
    use Spearmint
    alias Demo.Systems.SpawnHero
    alias Demo.Systems.MoveHero
    alias Demo.Systems.RestoreEnergy

    @impl Spearmint
    def setup(data) do
      data
      |> Spearmint.add_startup_system(SpawnHero)
      |> Spearmint.add_system(RestoreEnergy, run_if: [{__MODULE__, :energy_not_max?}])
      |> Spearmint.add_system(MoveHero, run_after: [RestoreEnergy])
      |> Spearmint.add_frame_end_system(Spearmint.System.Timer)
    end

    @spec energy_not_max? :: boolean()
    def energy_not_max? do
      energy_lookup =
        Spearmint.Query.select({Demo.Components.Energy}, with: [Demo.Components.Hero])
        |> Spearmint.Query.one()

      case energy_lookup do
        {%Demo.Components.Energy{current: current, max: max}} ->
          current < max

        _else ->
          false
      end
    end

    defmodule Components do
      defmodule Hero do
        use Spearmint.Component, state: [name: "Hero"]

        @spec fetch :: {:ok, Spearmint.Entity.t()} | {:error, :not_found}
        def fetch do
          entity_lookup =
            Spearmint.Query.select({Spearmint.Entity}, with: [Components.Hero])
            |> Spearmint.Query.one()

          case entity_lookup do
            {%Spearmint.Entity{} = entity} -> {:ok, entity}
            _else -> {:error, :not_found}
          end
        end
      end

      defmodule Energy do
        use Spearmint.Component, state: [current: 50, max: 100]
      end

      defmodule Position do
        use Spearmint.Component, state: [x: 0, y: 0]
      end

      defmodule EnergyTimer do
        use Spearmint.Template.Component.Timer,
          state: [
            duration: 3000,
            time: 3000,
            event: Demo.Events.EnergyTimerFinished,
            mode: :repeat
          ]
      end
    end

    defmodule Entities do
      defmodule Hero do
        @spec new() :: Spearmint.Entity.entity_spec()
        def new do
          {Spearmint.Entity,
           components: [
             Demo.Components.Hero,
             Demo.Components.Energy,
             Demo.Components.Position,
             Demo.Components.EnergyTimer
           ]}
        end

        def fetch do
          hero_lookup =
            Spearmint.Query.select({Spearmint.Entity}, with: [Components.Hero])
            |> Spearmint.Query.one()

          case hero_lookup do
            {%Spearmint.Entity{} = entity} -> {:ok, entity}
            _else -> {:error, :not_found}
          end
        end
      end
    end

    defmodule Events do
      defmodule MoveHero do
        use Spearmint.Event, fields: [:direction]
      end

      defmodule HeroMoved do
        use Spearmint.Event
      end

      defmodule EnergyTimerFinished do
        use Spearmint.Template.Event.Timer
      end
    end

    defmodule Systems do
      defmodule SpawnHero do
        use Spearmint.System, lock_components: [], event_subscriptions: []

        @impl Spearmint.System.WithoutEventSubscriptions
        def run(_frame) do
          %Spearmint.Entity{} = Spearmint.Command.spawn_entity!(Demo.Entities.Hero.new())
        end
      end

      defmodule MoveHero do
        use Spearmint.System,
          lock_components: [Demo.Components.Position, Demo.Components.Energy],
          event_subscriptions: [Demo.Events.MoveHero]

        alias Demo.Components

        @impl Spearmint.System.WithEventSubscriptions
        def run(%Demo.Events.MoveHero{direction: direction}, _frame) do
          components =
            Spearmint.Query.select({Components.Position, Components.Energy},
              with: [Components.Hero]
            )
            |> Spearmint.Query.one()

          with {position, energy} <- components,
               :ok <- validate_enough_energy_to_move(energy) do
            Spearmint.Command.update_components!([
              {energy, current: energy.current - 1},
              {position, update_coordinates(position, direction)}
            ])

            Spearmint.event(Demo.Events.HeroMoved)
          end
        end

        defp validate_enough_energy_to_move(%Components.Energy{current: current_energy}) do
          if current_energy >= 1 do
            :ok
          else
            {:error, :not_enough_energy}
          end
        end

        defp update_coordinates(%Components.Position{x: x, y: y}, direction) do
          case direction do
            :up -> [x: x, y: y + 1]
            :down -> [x: x, y: y - 1]
            :left -> [x: x - 1, y: y]
            :right -> [x: x + 1, y: y]
            _else -> [x: x, y: y]
          end
        end
      end

      defmodule RestoreEnergy do
        use Spearmint.System,
          lock_components: [Demo.Components.Energy],
          event_subscriptions: [Demo.Events.EnergyTimerFinished]

        @impl Spearmint.System.WithEventSubscriptions
        def run(%Demo.Events.EnergyTimerFinished{entity_id: entity_id}, _frame) do
          with {:ok, entity} <- Spearmint.Query.fetch_entity(entity_id),
               {:ok, energy} <- Spearmint.Query.fetch_component(entity, Demo.Components.Energy) do
            Spearmint.Command.update_component!(energy, current: energy.current + 1)
          end
        end
      end
    end

    defmodule Api do
      @spec fetch_hero_details() :: {:ok, map()} | {:error, :not_found}
      def fetch_hero_details do
        hero_details_lookup =
          Spearmint.Query.select(
            {Spearmint.Entity, Demo.Components.Hero, Demo.Components.Energy,
             Demo.Components.Position}
          )
          |> Spearmint.Query.one()

        case hero_details_lookup do
          {_hero_entity, hero, energy, position} ->
            {:ok,
             %{
               name: hero.name,
               energy: energy.current,
               max_energy: energy.max,
               pos_x: position.x,
               pos_y: position.y
             }}

          _else ->
            {:error, :not_found}
        end
      end

      @spec move_hero(direction :: :up | :down | :left | :right) :: :ok
      def move_hero(direction) do
        Spearmint.event({Demo.Events.MoveHero, direction: direction})
      end
    end

    test "Hero Spawns" do
      {:ok, sim_pid} = Spearmint.Simulation.start_link(Demo, 0)
      Spearmint.System.debug(system_module: Demo.Systems.SpawnHero)
      Spearmint.Simulation.prepare()

      assert not is_nil(Demo.Entities.Hero.fetch())

      assert {:ok, %{name: "Hero", energy: 50, max_energy: 100, pos_x: 0, pos_y: 0}} ==
               Demo.Api.fetch_hero_details()

      Spearmint.Simulation.stop()
      assert not Process.alive?(sim_pid)
    end

    test "Hero moves" do
      {:ok, sim_pid} = Spearmint.Simulation.start_link(Demo, 0)
      Spearmint.System.debug(system_module: Demo.Systems.SpawnHero)
      Spearmint.Simulation.prepare()

      assert not is_nil(Demo.Entities.Hero.fetch())

      assert {:ok, %{name: "Hero", energy: 50, max_energy: 100, pos_x: 0, pos_y: 0}} ==
               Demo.Api.fetch_hero_details()

      Demo.Api.move_hero(:up)
      Spearmint.Simulation.process_frame()

      assert {:ok, %{name: "Hero", energy: 49, max_energy: 100, pos_x: 0, pos_y: 1}} ==
               Demo.Api.fetch_hero_details()

      Spearmint.Simulation.stop()
      assert not Process.alive?(sim_pid)
    end
  end
end
