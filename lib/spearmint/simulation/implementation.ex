# Forked from ECSpanse 0.10.1 https://github.com/iacobson/ecspanse/releases/tag/v0.10.1
# Modifications Copyright (C) 2026 Aaron Schmidlkofer

defmodule Spearmint.Simulation.Implementation do
  @moduledoc """
  Contains the current state and the business logic for progressing the state of a simulation.
  """

  alias Spearmint.Frame
  alias Spearmint.System
  alias Spearmint.Util

  @type t :: %__MODULE__{
          status:
            :startup_systems
            | :frame_start_systems
            | :batch_systems
            | :frame_end_systems
            | :all_systems_run
            | :frame_ended,
          ecspanse_module: module(),
          system_run_conditions_map: map(),
          startup_resources: list(Spearmint.Resource.resource_spec()),
          startup_states: list(Spearmint.State.state_spec()),
          startup_systems: list(Spearmint.System.t()),
          frame_start_systems: list(Spearmint.System.t()),
          batch_systems: list(list(Spearmint.System.t())),
          frame_end_systems: list(Spearmint.System.t()),
          shutdown_systems: list(Spearmint.System.t()),
          scheduled_systems: list(Spearmint.System.t()),
          system_modules: MapSet.t(module()),
          ecs_version: non_neg_integer(),
          frame_data: Frame.t(),
          events_ets_table: atom()
        }

  @enforce_keys [
    :ecspanse_module,
    :ecs_version
  ]

  defstruct status: :startup_systems,
            ecspanse_module: nil,
            system_run_conditions_map: %{},
            startup_resources: [],
            startup_states: [],
            startup_systems: [],
            frame_start_systems: [],
            batch_systems: [],
            frame_end_systems: [],
            shutdown_systems: [],
            scheduled_systems: [],
            system_modules: MapSet.new(),
            ecs_version: 0,
            frame_data: %Frame{},
            events_ets_table: nil

  @spec new(atom(), non_neg_integer()) :: Spearmint.Simulation.Implementation.t()
  def new(ecspanse_module, ecs_version) do
    # The main reason for using ETS tables are:
    # - keep under control the GenServer memory usage
    # - eliminate GenServer bottlenecks. Various Systems or Queries can read directly from the ETS tables.

    # This is the main ETS table that holds the components state
    # as a list of `{{Spearmint.Entity.id(), component_module :: module()}, tags :: list(atom()),component_state :: struct()}`
    # All processes can read and write to this table. But writing should only be done through Commands.
    # The race condition is handled by the System Component locking.
    # Commands should validate that only Systems are writing to this table.
    :ets.new(Util.components_state_ets_table(), [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: :auto
    ])

    # This is the ETS table that holds the resources state
    # as a list of `{resource_module :: module(), resource_state :: struct()}`
    # All processes can read and write to this table.
    # But writing should only be done through Commands.
    # Commands should validate that only Systems are writing to this table.
    :ets.new(Util.resources_state_ets_table(), [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: false
    ])

    # These ETS tables stores Events as a list of event structs wrapped
    # in a tuple {{MyEventModule, key :: any()}, %MyEvent{}}.
    # There are 2 event tables that alternate every frame.
    # While the events in one are being processed, the other is being filled.
    # Every frame, the objects in the processed table are deleted.
    # Any process can read and write to this table.
    # But the logic responsible to write to this table should check the stored values are actually event structs.
    # Before being sent to the Systems, the events are sorted by their inserted_at timestamp, and group in batches.
    # The batches are determined by the uniqueness of the event {EventModule, key} per batch.

    Enum.each(Util.events_ets_tables(), fn table ->
      :ets.new(table, [
        :duplicate_bag,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])
    end)

    # This ETS table holds the value of the currently used events table.
    # See the above comment for more details.
    # It is optimized for multiple reads
    :ets.new(Util.dual_events_ets_table(), [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: false
    ])

    events_ets_table = List.first(Util.events_ets_tables())

    :ets.insert(
      Util.dual_events_ets_table(),
      {:current, events_ets_table}
    )

    Spearmint.Projection.Supervisor.start_link()

    state! = %Spearmint.Simulation.Implementation{
      ecspanse_module: ecspanse_module,
      ecs_version: ecs_version,
      events_ets_table: events_ets_table
    }

    %Spearmint.Data{operations: operations} = state!.ecspanse_module.setup(%Spearmint.Data{})

    state! = operations |> Enum.reverse() |> apply_operations(state!)

    # TODO Something more elegant than pretending to be a system during startup
    Process.put(:ecs_process_type, :system)
    Process.put(:system_execution, :sync)

    for state_spec <- state!.startup_states do
      case state_spec do
        {state_module, initial_state} when is_atom(state_module) and is_atom(initial_state) ->
          Spearmint.Command.insert_resource!({state_module, [current: initial_state]})

        state_module when is_atom(state_module) ->
          Spearmint.Command.insert_resource!(state_module)
      end
    end

    for resource_spec <- state!.startup_resources do
      Spearmint.Command.insert_resource!(resource_spec)
    end

    Process.delete(:ecs_process_type)
    Process.delete(:system_execution)

    state!
  end

  @spec run_shutdown_systems(Spearmint.Simulation.Implementation.t()) :: :ok
  def run_shutdown_systems(%__MODULE__{} = state) do
    # Running shutdown_systems. Those cannot run in the standard way because the process is shutting down.
    # They are executed sync, in the ordered they were added.
    Enum.each(state.shutdown_systems, fn system ->
      task =
        Task.async(fn ->
          prepare_system_process(system, state)
          system.module.run(state.frame_data)
        end)

      Task.await(task)
    end)
  end

  @spec prepare(t()) :: t()
  def prepare(%__MODULE__{} = state) do
    state = %{
      state
      | scheduled_systems: state.startup_systems,
        frame_data: %Frame{event_batches: []}
    }

    :ets.delete_all_objects(state.events_ets_table)
    Util.switch_events_ets_table()

    run_next_system(state)
  end

  @spec process_frame(t()) :: t()
  def process_frame(%__MODULE__{} = state!) do
    events_ets_table = Util.events_ets_table()
    Util.switch_events_ets_table()

    state! = %Spearmint.Simulation.Implementation{state! | events_ets_table: events_ets_table}

    event_batches =
      state!.events_ets_table
      |> :ets.tab2list()
      |> batch_events()

    # Delete all events from the ETS table
    :ets.delete_all_objects(state!.events_ets_table)

    # the systems run conditions are refreshed every frame
    # this is intentional behaviour for performance reasons
    # but also to avoid inconsistencies in the components
    state! = refresh_system_run_conditions_map(state!)

    state! = %{
      state!
      | status: :frame_start_systems,
        scheduled_systems: state!.frame_start_systems,
        frame_data: %Frame{
          event_batches: event_batches
        }
    }

    run_next_system(state!)
  end

  # finished running startup systems (sync) and starting the loop
  @spec run_next_system(Spearmint.Simulation.Implementation.t()) ::
          Spearmint.Simulation.Implementation.t()
  def run_next_system(
        %Spearmint.Simulation.Implementation{scheduled_systems: [], status: :startup_systems} =
          state
      ) do
    state
  end

  # finished running systems at the beginning of the frame (sync) and scheduling the batch systems
  def run_next_system(
        %Spearmint.Simulation.Implementation{scheduled_systems: [], status: :frame_start_systems} =
          state
      ) do
    state = %{state | status: :batch_systems, scheduled_systems: state.batch_systems}

    run_next_system(state)
  end

  # finished running batch systems (async per batch) and scheduling the end of the frame systems
  def run_next_system(
        %Spearmint.Simulation.Implementation{scheduled_systems: [], status: :batch_systems} =
          state
      ) do
    state = %{state | status: :frame_end_systems, scheduled_systems: state.frame_end_systems}

    run_next_system(state)
  end

  # finished running systems at the end of the frame (sync) and scheduling the end of frame
  def run_next_system(
        %Spearmint.Simulation.Implementation{scheduled_systems: [], status: :frame_end_systems} =
          state
      ) do
    finished_running_all_systems(state)
  end

  # running batch (async) systems. This runs only for `batch_systems` status
  def run_next_system(
        %__MODULE__{
          scheduled_systems: [systems_batch | batches],
          status: :batch_systems
        } = state
      ) do
    systems_batch =
      Enum.filter(systems_batch, &run_system?(&1, state.system_run_conditions_map))

    case systems_batch do
      [] ->
        state = %{state | scheduled_systems: batches}
        run_next_system(state)

      systems_batch ->
        # Choosing this approach instead of using `Task.async_stream` because
        # we don't want to block the server while processing the batch
        # Also it re-uses the same code as the sync systems
        Task.async_stream(
          systems_batch,
          fn x ->
            run_system(x, state)
          end,
          ordered: false,
          timeout: :infinity
        )
        |> Stream.run()

        # TODO All systems will probably need to be sync to protect the state.

        state = %{state | scheduled_systems: batches}
        run_next_system(state)
    end
  end

  # running sync systems
  def run_next_system(
        %Spearmint.Simulation.Implementation{scheduled_systems: [system | systems]} = state
      ) do
    if run_system?(system, state.system_run_conditions_map) do
      run_system(system, state)
    end

    state = %{state | scheduled_systems: systems}
    run_next_system(state)
  end

  # finishing the frame systems execution
  # scheduling projections
  @spec finished_running_all_systems(Spearmint.Simulation.Implementation.t()) ::
          Spearmint.Simulation.Implementation.t()
  def finished_running_all_systems(%Spearmint.Simulation.Implementation{} = state) do
    projection_pids =
      Spearmint.Projection.Supervisor
      |> DynamicSupervisor.which_children()
      |> Enum.map(fn {_undefined, pid, _type, _module} -> pid end)

    projection_pids
    |> Task.async_stream(
      fn pid ->
        # Ensure against race conditions when the projection was terminated
        try do
          GenServer.call(pid, :update)
        catch
          :exit, {:noproc, {GenServer, :call, _reason}} ->
            :ok
        end
      end,
      ordered: false,
      max_concurrency: length(projection_pids) + 1
    )
    |> Stream.run()

    state = %Spearmint.Simulation.Implementation{
      state
      | status: :all_systems_run
    }

    finished_projection_updates(state)
  end

  # finished the frame projection updates
  @spec finished_projection_updates(Spearmint.Simulation.Implementation.t()) ::
          Spearmint.Simulation.Implementation.t()
  def finished_projection_updates(%Spearmint.Simulation.Implementation{} = state) do
    %Spearmint.Simulation.Implementation{state | status: :frame_ended}
  end

  ### HELPER ###

  # TODO refactor to be private
  @spec run_system(any(), any()) :: :ok
  def run_system(system, %__MODULE__{} = state) do
    task =
      Task.async(fn ->
        prepare_system_process(system, state)
        system.module.schedule_run(state.frame_data)
        :ok
      end)

    Task.await(task, :infinity)
    :ok
  end

  # This happens in the System process
  @spec prepare_system_process(any(), any()) :: any()
  defp prepare_system_process(system, state) do
    Process.put(:ecs_process_type, :system)
    Process.put(:system_execution, system.execution)
    Process.put(:system_module, system.module)
    Process.put(:locked_components, system.module.__locked_components__())
    Process.put(:ecs_version, state.ecs_version)
  end

  defp apply_operations([], state), do: state

  defp apply_operations([operation | operations], state) do
    %Spearmint.Simulation.Implementation{} = state = apply_operation(operation, state)
    apply_operations(operations, state)
  end

  # persist startup resources specs
  defp apply_operation(
         {:insert_resource, resource_spec},
         %Spearmint.Simulation.Implementation{} = state
       ) do
    %Spearmint.Simulation.Implementation{
      state
      | startup_resources: state.startup_resources ++ [resource_spec]
    }
  end

  # persist states specs
  defp apply_operation({:init_state, state_spec}, %Spearmint.Simulation.Implementation{} = state) do
    %Spearmint.Simulation.Implementation{
      state
      | startup_states: state.startup_states ++ [state_spec]
    }
  end

  # batch async systems
  defp apply_operation(
         {:add_system,
          %System{queue: :batch_systems, module: system_module, run_after: []} = system},
         state
       ) do
    state = validate_unique_system(system_module, state)

    batch_systems = Map.get(state, :batch_systems)

    # should return a list of lists
    new_batch_systems = batch_system(system, batch_systems, [])

    state
    |> Map.put(:batch_systems, new_batch_systems)
    |> Map.put(
      :system_run_conditions_map,
      add_to_system_run_conditions_map(state.system_run_conditions_map, system)
    )
  end

  defp apply_operation(
         {:add_system,
          %System{queue: :batch_systems, module: system_module, run_after: after_systems} = system},
         state
       ) do
    state = validate_unique_system(system_module, state)
    batch_systems = Map.get(state, :batch_systems)

    system_modules = batch_systems |> List.flatten() |> Enum.map(& &1.module)

    non_existing_systems = after_systems -- system_modules

    if not Enum.empty?(non_existing_systems) do
      raise "Systems #{Kernel.inspect(non_existing_systems)} does not exist. A system can run only after existing systems"
    end

    # should return a list of lists
    new_batch_systems = batch_system_after(system, after_systems, batch_systems, [])

    state
    |> Map.put(:batch_systems, new_batch_systems)
    |> Map.put(
      :system_run_conditions_map,
      add_to_system_run_conditions_map(state.system_run_conditions_map, system)
    )
  end

  # add sequential systems to their queues
  defp apply_operation(
         {:add_system, %System{queue: queue, module: system_module} = system},
         %Spearmint.Simulation.Implementation{} = state
       ) do
    state = validate_unique_system(system_module, state)

    state
    |> Map.put(queue, Map.get(state, queue) ++ [system])
    |> Map.put(
      :system_run_conditions_map,
      add_to_system_run_conditions_map(state.system_run_conditions_map, system)
    )
  end

  @spec validate_unique_system(atom(), Spearmint.Simulation.Implementation.t()) ::
          Spearmint.Simulation.Implementation.t()
  defp validate_unique_system(system_module, %Spearmint.Simulation.Implementation{} = state) do
    Spearmint.Util.validate_ecs_type(
      system_module,
      :system,
      ArgumentError,
      "The module #{Kernel.inspect(system_module)} must be a System"
    )

    if MapSet.member?(state.system_modules, system_module) do
      raise "System #{Kernel.inspect(system_module)} already exists. Server systems must be unique."
    end

    %Spearmint.Simulation.Implementation{
      state
      | system_modules: MapSet.put(state.system_modules, system_module)
    }
  end

  defp batch_system(system, [], []) do
    [[system]]
  end

  defp batch_system(system, [], checked_batches) do
    checked_batches ++ [[system]]
  end

  defp batch_system(system, [batch | batches], checked_batches) do
    system_locked_components = system.module.__locked_components__()

    batch_locked_components =
      batch |> Enum.map(& &1.module.__locked_components__()) |> List.flatten()

    if batch_locked_components -- system_locked_components == batch_locked_components do
      updated_batch = batch ++ [system]
      checked_batches ++ [updated_batch] ++ batches
    else
      batch_system(system, batches, checked_batches ++ [batch])
    end
  end

  defp batch_system_after(system, [] = _after_systems, remaining_batches, checked_batches) do
    batch_system(system, remaining_batches, checked_batches)
  end

  defp batch_system_after(system, after_system_modules, [batch | batches], checked_batches) do
    remaining_after_systems = after_system_modules -- Enum.map(batch, & &1.module)

    batch_system_after(
      system,
      remaining_after_systems,
      batches,
      checked_batches ++ [batch]
    )
  end

  # builds a map with all running conditions from all systems
  # this allows to run the conditions only per frame
  defp add_to_system_run_conditions_map(
         existing_conditions,
         %{run_conditions: run_conditions} = _system
       ) do
    Enum.reduce(run_conditions, existing_conditions, fn condition, acc ->
      Map.put(acc, condition, false)
    end)

    # Adding false as initial value for the condition
    # because this cannot run on startup systems
    # this will be updated in the refresh_system_run_conditions_map
  end

  # takes state and returns state
  # TODO refactor to be private
  @spec refresh_system_run_conditions_map(Spearmint.Simulation.Implementation.t()) :: any()
  def refresh_system_run_conditions_map(%Spearmint.Simulation.Implementation{} = state) do
    Enum.reduce(state.system_run_conditions_map, state, fn {{module, function, args} = condition,
                                                            _value},
                                                           %Spearmint.Simulation.Implementation{} =
                                                             state ->
      result = apply(module, function, args)

      unless is_boolean(result) do
        raise "System run condition functions must return a boolean. Got: #{Kernel.inspect(result)}. For #{Kernel.inspect({module, function, args})}."
      end

      %Spearmint.Simulation.Implementation{
        state
        | system_run_conditions_map: Map.put(state.system_run_conditions_map, condition, result)
      }
    end)
  end

  # TODO refactor to be private
  @spec run_system?(any(), any()) :: boolean()
  def run_system?(system, run_conditions_map) do
    Enum.all?(system.run_conditions, fn condition ->
      Map.get(run_conditions_map, condition) == true
    end)
  end

  # TODO refactor to be private
  @spec batch_events(any()) :: [list()]
  def batch_events(events) do
    events
    |> do_event_batches([])
  end

  defp do_event_batches([], batches), do: batches

  defp do_event_batches(events, batches) do
    current_events = Enum.uniq_by(events, fn {{_module, batch_key}, _v} -> batch_key end)

    batch =
      Enum.map(current_events, fn {_key, v} -> v end)

    remaining_events = events -- current_events
    do_event_batches(remaining_events, batches ++ [batch])
  end
end
