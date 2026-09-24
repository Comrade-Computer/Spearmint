# Forked from ECSpanse 0.10.1 https://github.com/iacobson/ecspanse/releases/tag/v0.10.1
# Modifications Copyright (C) 2026 Aaron Schmidlkofer

defmodule Spearmint do
  @moduledoc """
  Spearmint is an Entity Component System (ECS) framework for Elixir.

  > #### Note {: .info}
  > Spearmint is not a game engine, but a flexible foundation
  > for managing state and building logic, offering features like:
  > - flexible queries with multiple filters
  > - dynamic bidirectional relationships
  > - versatile tagging capabilities
  > - system event subscriptions
  > - asynchronous system execution

  The core structure of the Spearmint library is:

  - `Spearmint`: The main module used to configure and interact with the library.
  - `Spearmint.Server`: The server orchestrates the execution of systems and the storage of components, resources, and events.
  - `Spearmint.Entity`: A simple struct with an ID, serving as a holder for components.
  - `Spearmint.Component`: A struct that may hold state information or act as a simple label for an entity.
  - `Spearmint.System`: Holds the application core logic. Systems run every frame, either synchronously or asynchronously.
  - `Spearmint.Resource`: Global state storage, similar to components but not tied to a specific entity. Resources can only be created, updated, and deleted by synchronously executed systems.
  - `Spearmint.Query`: A tool for retrieving entities, components, or resources.
  - `Spearmint.Command`: A mechanism for changing components and resources state. They can only be triggered from a system.
  - `Spearmint.Event`: A mechanism for triggering events, which can be listened to by systems. It is the way to communicate externally with the systems.

  ## Usage

  To use Spearmint, a module needs to be created, invoking `use Spearmint`. This implements the `Spearmint` behaviour, so the `setup/1` callback must be defined. All the systems and their execution order are defined in the `setup/1` callback.

  ## Examples

  ```elixir
  defmodule TestServer1 do
    use Spearmint, version: 1

    def setup(data) do
      data
      |> add_startup_system(Demo.Systems.SpawnHero)
      |> add_frame_start_system(Demo.Systems.PurchaseItem)
      |> add_system(Demo.Systems.MoveHero)
      |> add_frame_end_system(Spearmint.System.Timer)
      |> add_shutdown_system(Demo.Systems.Cleanup)
    end
  end
  ```

  > #### Info  {: .info}
  > The `Spearmint` system scheduling functions are imported by default
  > for the setup module that `use Spearmint`

  ## Configuration

  The following configuration options are available:
  - `:version` (optional) - non negative integer - the version of the ECS game logic.
  Can be used to determine backwards compatibility when saving and loading state(see `Spearmint.Snapshot` for details).
  Defaults to 0.
  """

  alias __MODULE__
  alias Spearmint.Util

  require Logger

  defmodule Data do
    @moduledoc """
    The `Data` module defines a struct that holds the state of the Spearmint initialization process.
    This struct is passed to the `setup/1` callback, which is used to define the running systems.
    After the initialization process the `Data` struct is not relevant anymore.
    """

    @typedoc """
    The data used for the Spearmint initialization process.
    """
    @type t :: %__MODULE__{
            operations: operations(),
            system_set_options: map()
          }

    @type operation ::
            {:add_system, Spearmint.System.system_queue(), Spearmint.System.t()}
            | {:add_system, :batch_systems, Spearmint.System.t(), opts :: keyword()}
    @type operations :: list(operation())

    defstruct operations: [], system_set_options: %{}
  end

  @doc """
  The `setup/1` callback is called on Spearmint startup and is the place to define the running systems.
  It takes an `Spearmint.Data` struct as an argument and returns an updated struct.

  ## Examples

  ```elixir
  defmodule MyProject do
    use Spearmint

    @impl Spearmint
    def setup(%Spearmint.Data{} = data) do
      data
      |> Spearmint.Server.add_system(Demo.Systems.MoveHero)
    end
  end
  ```
  """
  @callback setup(Spearmint.Data.t()) :: Spearmint.Data.t()

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      @behaviour Spearmint

      import Spearmint,
        only: [
          insert_resource: 2,
          init_state: 2,
          add_startup_system: 2,
          add_frame_start_system: 2,
          add_frame_start_system: 3,
          add_system: 2,
          add_system: 3,
          add_frame_end_system: 2,
          add_frame_end_system: 3,
          add_shutdown_system: 2,
          add_system_set: 2,
          add_system_set: 3
        ]

      version = Keyword.get(opts, :version, 0)

      unless is_integer(version) do
        raise ArgumentError,
              "The option :version must be an integer in the module #{Kernel.inspect(__MODULE__)}"
      end

      Module.register_attribute(__MODULE__, :ecs_version, accumulate: false)
      Module.put_attribute(__MODULE__, :ecs_version, version)

      @doc false
      def child_spec(_arg) do
        payload = %{
          ecspanse_module: __MODULE__,
          ecs_version: @ecs_version
        }

        %{
          id: __MODULE__,
          start: {Spearmint.Server, :start_link, [payload]},
          restart: :permanent
        }
      end
    end
  end

  @doc """
  Initializes a state at startup.
  > #### Note {: .info}
  > States can be initialized once, only at startup.
  """
  @spec init_state(Spearmint.Data.t(), Spearmint.State.state_spec()) :: Spearmint.Data.t()
  def init_state(%Spearmint.Data{operations: operations} = data, state_spec) do
    %Spearmint.Data{data | operations: [{:init_state, state_spec} | operations]}
  end

  @doc """
  Inserts a new global resource at startup.
  See `Spearmint.Resource` and `Spearmint.Command.insert_resource!/1` for more info.
  """
  @spec insert_resource(Spearmint.Data.t(), Spearmint.Resource.resource_spec()) ::
          Spearmint.Data.t()
  def insert_resource(%Spearmint.Data{operations: operations} = data, resource_spec) do
    %Spearmint.Data{data | operations: [{:insert_resource, resource_spec} | operations]}
  end

  @doc """
  Schedules a startup system.

  A startup system runs only once during the Spearmint startup process. Startup systems do not take any options.

  ## Examples

    ```elixir
    Spearmint.add_startup_system(Spearmint_data, Demo.Systems.SpawnHero)
    ```
  """
  @spec add_startup_system(Spearmint.Data.t(), system_module :: module()) :: Spearmint.Data.t()
  def add_startup_system(%Spearmint.Data{operations: operations} = data, system_module) do
    system = %Spearmint.System{
      module: system_module,
      queue: :startup_systems,
      execution: :sync,
      run_conditions: []
    }

    %Spearmint.Data{data | operations: [{:add_system, system} | operations]}
  end

  @doc """
  Schedules a frame start system to be executed each frame during the game loop.

  A frame start system is executed synchronously at the beginning of each frame.
  Sync systems are executed in the order they were added.

  ## Options

  - See the `add_system/3` function for more information about the options.

  ## Examples

    ```elixir
    Spearmint.add_frame_start_system(Spearmint_data, Demo.Systems.PurchaseItem)
    ```
  """

  @spec add_frame_start_system(Spearmint.Data.t(), system_module :: module(), opts :: keyword()) ::
          Spearmint.Data.t()
  def add_frame_start_system(
        %Spearmint.Data{operations: operations} = data,
        system_module,
        opts \\ []
      ) do
    opts = merge_system_options(opts, data.system_set_options)

    system =
      add_run_conditions(
        %Spearmint.System{module: system_module, queue: :frame_start_systems, execution: :sync},
        opts
      )

    %Spearmint.Data{data | operations: [{:add_system, system} | operations]}
  end

  @doc """
  Schedules an async system to be executed each frame during the game loop.

  ## Options

  - `:run_in_state` - a tuple of the state module using `Spearmint.State` and the atom state in which the system should run.
  - `:run_not_in_state` - same as `run_in_state`, but the system will run when the state is not the one provided.
  - `:run_if` - a list of tuples containing the module and function that define a condition for running the system. Eg. `[{MyModule, :my_function}]`. The function must return a boolean.
  - `:run_after` - only for async systems - a system or list of systems that must run before this system.

  ## Order of execution

  Systems are executed each frame during the game loop. Sync systems run in the order they were added to the data's operations list.
  Async systems are grouped in batches depending on the components they are locking.
  See the `Spearmint.System` module for more information about component locking.

  The order in which async systems run can pe specified using the `run_after` option.
  This option takes a system or list of systems that must be run before the current system.

  When using the `run_after: SystemModule1` or `run_after: [SystemModule1, SystemModule2]` option, the following rules apply:
  - The system(s) specified in `run_after` must be already scheduled. This prevents circular dependencies.
  - There is a deliberate choice to allow **only the `run_after`** ordering option. While a `run_before` option would simplify some relations, it can also introduce circular dependencies.

  Example of circular dependency:
  - System A
  - System B, run_before: System A
  - System C, run_after: System A, run_before: System B

  > #### Info  {: .info}
  > The 'run_after' option does not depend on the "before" system being executed or not
  > (eg. when the "before" system subscribes to an event that is not triggered this frame).
  > The system will be executed anyway, even if the "before" system is not executed this frame.
  > The `:run_after` option is evaluated only once, at server start-up,
  > when the async systems are grouped together into batches.
  > Then the scheduler tries to execute every system in every batch.

  ## Conditionally running systems

  The systems can be programmed to run only if some specific conditions are met.
  The conditions can be:
  - state related: `run_in_state` and `run_not_in_state`
  - custom conditions: `run_if` a function returns `true`

  `run_in_state` supports a single state. If a combination of states is needed to run a system, the `run_if` option can be used.

    ```elixir
    Spearmint.add_system(
      Spearmint_data,
      Demo.Systems.MoveHero,
      run_if: [{Demo.States.Game, :in_market_place}]
    )

    def in_market_place do
      Demo.States.Game.get_state!() == :paused and
      Demo.States.Location.get_state!() == :market
    end
    ```

  It is important to note that the run conditions are evaluated only once per frame, at the beginning of the frame.
  So any change in the running conditions will be picked up in the next frame.

  If the system is part of a system set, and both the system and the system set have run conditions, the conditions are cumulative.
  All the conditions must be met for the system to run.

  ## Examples

    ```elixir
    Spearmint.add_system(
      Spearmint_data,
      Demo.Systems.MoveHero,
      run_in_state: {Demo.States.Game, [:play]},
      run_after: [Demo.Systems.RestoreEnergy]
    )
    ```
  """
  @spec add_system(Spearmint.Data.t(), system_module :: module(), opts :: keyword()) ::
          Spearmint.Data.t()
  def add_system(%Spearmint.Data{operations: operations} = data, system_module, opts \\ []) do
    opts = merge_system_options(opts, data.system_set_options)

    after_system = Keyword.get(opts, :run_after)

    run_after =
      case after_system do
        nil -> []
        after_systems when is_list(after_systems) -> after_systems
        after_system when is_atom(after_system) -> [after_system]
      end

    system =
      add_run_conditions(
        %Spearmint.System{
          module: system_module,
          queue: :batch_systems,
          execution: :async,
          run_after: run_after
        },
        opts
      )

    %Spearmint.Data{data | operations: [{:add_system, system} | operations]}
  end

  @doc """
  Schedules a frame end system to be executed each frame during the game loop.

  A frame end system is executed synchronously at the end of each frame.
  Sync systems are executed in the order they were added.

  ## Options

  - See the `add_system/3` function for more information about the options.

  ## Examples

    ```elixir
    Spearmint.add_frame_end_system(Spearmint_data, Spearmint.Systems.Timer)
    ```
  """
  @spec add_frame_end_system(Spearmint.Data.t(), system_module :: module(), opts :: keyword()) ::
          Spearmint.Data.t()
  def add_frame_end_system(
        %Spearmint.Data{operations: operations} = data,
        system_module,
        opts \\ []
      ) do
    opts = merge_system_options(opts, data.system_set_options)

    system =
      add_run_conditions(
        %Spearmint.System{module: system_module, queue: :frame_end_systems, execution: :sync},
        opts
      )

    %Spearmint.Data{data | operations: [{:add_system, system} | operations]}
  end

  @doc """
  Schedules a shutdown system.

  A shutdown system runs only once when the Spearmint.Server terminates. Shutdown systems do not take any options.
  This is useful for cleaning up or saving the game state.

  ## Examples

    ```elixir
    Spearmint.add_shutdown_system(Spearmint_data, Demo.Systems.Cleanup)
    ```
  """
  @spec add_shutdown_system(Spearmint.Data.t(), system_module :: module()) :: Spearmint.Data.t()
  def add_shutdown_system(%Spearmint.Data{operations: operations} = data, system_module) do
    system = %Spearmint.System{
      module: system_module,
      queue: :shutdown_systems,
      execution: :sync,
      run_conditions: []
    }

    %Spearmint.Data{data | operations: [{:add_system, system} | operations]}
  end

  @doc """
  Convenient way to group together related systems.

  New systems can be added to the set using the `add_system_*` functions.
  System sets can also be nested.


  ## Options

  The set options that applied on top of each system options in the set.
  - See the `add_system/3` function for more information about the options.

  ## Examples

  ```elixir
  defmodule Demo do
    use Spearmint

    @impl Spearmint
    def setup(data) do
      data
      |> Spearmint.add_system_set({Demo.HeroSystemSet, :setup}, [run_in_state: {Demo.States.Game, :play}])
    end

    defmodule HeroSystemSet do
      def setup(data) do
        data
        |> Spearmint.add_system(Demo.Systems.MoveHero, [run_after: Demo.Systems.RestoreEnergy])
        |> Spearmint.add_system_set({Demo.ItemsSystemSet, :setup})
      end
    end

    defmodule ItemsSystemSet do
      def setup(data) do
        data
        |> Spearmint.add_system(Demo.Systems.PickupItem)
      end
    end
  end
  ```
  """
  @spec add_system_set(Spearmint.Data.t(), {module(), function :: atom}, opts :: keyword()) ::
          Spearmint.Data.t()
  def add_system_set(%Spearmint.Data{} = data!, {module, function}, opts \\ []) do
    # add the system set options to the data
    # the Server system_set_options is a map with the key {module, function} for every system set
    data! = %Spearmint.Data{
      data!
      | system_set_options: Map.put(data!.system_set_options, {module, function}, opts)
    }

    data! = apply(module, function, [data!])

    # remove the system set options from the data
    case data! do
      %Spearmint.Data{} ->
        %Spearmint.Data{
          data!
          | system_set_options: Map.delete(data!.system_set_options, {module, function})
        }

      _else ->
        raise RuntimeError,
              "add_system_set second argument must return a %Spearmint.Data{} structure when called. Got #{inspect(data!)} from #{inspect({module, function})}"
    end
  end

  @doc """
  Retrieves the Spearmint Server process PID.
  If the data process is not found, it returns an error.

  ## Examples

    ```elixir
    Spearmint.fetch_pid()
    {:ok, %{name: data_name, pid: data_pid}}
    ```
  """
  # TODO Remove to discover lots of places where the singleton assumption is made
  @spec fetch_pid() ::
          {:ok, pid()} | {:error, :not_found}
  def fetch_pid do
    case Process.whereis(Spearmint.Server) do
      pid when is_pid(pid) ->
        {:ok, pid}

      _else ->
        {:error, :not_found}
    end
  end

  @doc """
  Queues an event to be processed in the next frame.

  ## Options

  - `:batch_key` - A key for grouping multiple similar events in different batches within the same frame.
  The event scheduler groups the events into batches by unique `{EventModule, batch_key}` combinations.
  In most cases, the key may be an entity ID that either triggers or is impacted by the event.
  Defaults to `default`, meaning that similar events will be placed in separate batches.

  ## Examples

    ```elixir
      Spearmint.event({Demo.Events.MoveHero, direction: :up},  batch_key: hero_entity.id)
    ```
  """
  @spec event(
          Spearmint.Event.event_spec(),
          opts :: keyword()
        ) :: :ok
  def event(event_spec, opts \\ []) do
    batch_key = Keyword.get(opts, :batch_key, "default")

    event = prepare_event(event_spec, batch_key)

    :ets.insert(Util.events_ets_table(), event)

    :ok
  end

  defp prepare_event(event_spec, batch_key) do
    {event_module, key, event_payload} =
      case event_spec do
        {event_module, event_payload}
        when is_atom(event_module) and is_list(event_payload) ->
          validate_event(event_module)
          {event_module, batch_key, event_payload}

        event_module when is_atom(event_module) ->
          validate_event(event_module)
          {event_module, batch_key, []}
      end

    {{event_module, key}, struct!(event_module, event_payload)}
  end

  defp validate_event(event_module) do
    Spearmint.Util.validate_ecs_type(
      event_module,
      :event,
      ArgumentError,
      "The module #{Kernel.inspect(event_module)} must be a Event"
    )
  end

  # merge the system options with the system set options
  # this is the reason the conditional run states are a list
  defp merge_system_options(system_opts, system_set_opts)
       when is_list(system_opts) and is_map(system_set_opts) do
    system_set_opts = system_set_opts |> Map.values() |> List.flatten() |> Enum.uniq()

    (system_opts ++ system_set_opts)
    |> Enum.group_by(fn {k, _v} -> k end, fn {_k, v} -> v end)
    |> Enum.map(fn {k, v} -> {k, v |> List.flatten() |> Enum.uniq()} end)
  end

  defp add_run_conditions(%Spearmint.System{} = system, opts) do
    run_in_state = conditional_run_state(opts, :run_in_state)

    run_in_state_functions =
      Enum.map(run_in_state, fn {state_module, state} ->
        {Spearmint.Util, :run_system_in_state, [state_module, state]}
      end)

    run_not_in_state = conditional_run_state(opts, :run_not_in_state)

    run_not_in_state_functions =
      Enum.map(run_not_in_state, fn {state_module, state} ->
        {Spearmint.Util, :run_system_not_in_state, [state_module, state]}
      end)

    run_if =
      case Keyword.get(opts, :run_if, []) do
        {module, function} = condition when is_atom(module) and is_atom(function) -> [condition]
        conditions when is_list(conditions) -> conditions
      end

    run_if_functions =
      Enum.map(run_if, fn {module, function} ->
        {module, function, []}
      end)

    %Spearmint.System{
      system
      | run_conditions: run_in_state_functions ++ run_not_in_state_functions ++ run_if_functions
    }
  end

  defp conditional_run_state(opts, option) do
    # This is a list. See the `merge_system_options/2` function for more info.
    # The run state conditions from systems and system sets are cumulative.
    opts
    |> Keyword.get(option, [])
    |> Enum.map(fn
      {state_module, state} when is_atom(state_module) and is_atom(state) ->
        unless state in state_module.__states__() do
          raise ArgumentError,
                "Invalid system run condition for State: #{Kernel.inspect(state_module)}. The the run condition state must be an atom from: #{Kernel.inspect(state_module.__states__())}."
        end

        [{state_module, state}]

      state_run_condition ->
        raise ArgumentError,
              "Invalid system run condition: #{Kernel.inspect(state_run_condition)}. The run condition state must be tuple in the form `{StateModule, :state}`."
    end)
    |> List.flatten()
    |> Enum.uniq()
  end
end
