# Forked from ECSpanse 0.10.1 https://github.com/iacobson/ecspanse/releases/tag/v0.10.1
# Modifications Copyright (C) 2026 Aaron Schmidlkofer

defmodule Spearmint.System.Timer do
  @moduledoc """
  A special system provided by the framework that
  counts down the time for all the custom timer components.

  If the `timer` functionality is used, this system
  needs to be manually added in the `c:Spearmint.setup/1`
  callback as a sync system.

  See `Spearmint.Template.Component.Timer` for details.
  """

  use Spearmint.System
  alias Spearmint.Query

  @impl Spearmint.System.WithoutEventSubscriptions
  @spec run(Spearmint.Frame.t()) :: :ok
  def run(_frame) do
    Query.list_tagged_components([:ecs_timer])
    |> Stream.filter(fn timer -> timer.time > 0 and not timer.paused end)
    |> Enum.group_by(fn timer -> timer.mode end)
    |> Enum.each(fn
      {:repeat, timers} -> update_repeating(timers)
      {:once, timers} -> update_once(timers)
      {:temporary, timers} -> update_temporary(timers)
    end)
  end

  defp update_repeating(timers) do
    timers
    |> Enum.map(fn timer ->
      new_time = timer.time - 1

      if new_time <= 0 do
        entity = Query.get_component_entity(timer)
        event_spec = build_event_spec(timer, entity)
        Spearmint.event(event_spec, batch_key: entity.id)
        {timer, time: timer.duration}
      else
        {timer, time: new_time}
      end
    end)
    |> Spearmint.Command.update_components!()
  end

  defp update_once(timers) do
    timers
    |> Enum.map(fn timer ->
      new_time = timer.time - 1

      if new_time <= 0 do
        entity = Query.get_component_entity(timer)
        event_spec = build_event_spec(timer, entity)
        Spearmint.event(event_spec, batch_key: entity.id)
      end

      {timer, time: new_time}
    end)
    |> Spearmint.Command.update_components!()
  end

  defp update_temporary(timers) do
    %{update: update, remove: remove} =
      timers
      |> Enum.reduce(%{update: [], remove: []}, fn timer, acc ->
        new_time = timer.time - 1

        if new_time <= 0 do
          entity = Query.get_component_entity(timer)
          event_spec = build_event_spec(timer, entity)
          Spearmint.event(event_spec, batch_key: entity.id)
          %{acc | remove: [timer | acc.remove]}
        else
          %{acc | update: [{timer, time: new_time} | acc.update]}
        end
      end)

    Spearmint.Command.update_components!(update)
    Spearmint.Command.remove_components!(remove)
  end

  defp build_event_spec(timer, entity) do
    {timer.event, entity_id: entity.id}
  end
end
