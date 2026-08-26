# Forked from ECSpanse 0.10.1 https://github.com/iacobson/ecspanse/releases/tag/v0.10.1
# Modifications Copyright (C) 2026 Aaron Schmidlkofer

defmodule Spearmint.Event do
  @moduledoc """
  Heavily based on the fantastic ECSpanse library

  Events act as a one-way communication channel to Spearmint's ECS,
  enabling elements outside of the framework to dispatch data asynchronously into Spearmint Systems.
  Events are also used internally to communicate between Systems.
  The events are defined by invoking `use Spearmint.Event` in their module definition.

  Events are scheduled using the `Spearmint.event/2` function.
  Any events scheduled within the current frame will be batched and
  then made accessible to the systems in the following `t:Spearmint.Frame.t/0`.
  The batched events from the current frame are forgotten once that frame ends.
  This implies each system has a exactly one opportunity to process an event that has been scheduled.

  ## Options
    - `:fields` - a list with all the event struct keys and their initial values (if any)
    For example: `[:direction, type: :hero]`

  There are two ways of providing the events with their field values:

  1. At compile time, when invoking the `use Spearmint.Event`, by providing the `:fields` option.
    ```elixir
    defmodule Demo.Events.HeroMoved do
      use Spearmint.Event, fields: [:direction, type: :hero]
    end
    ```

  2. At runtime when creating the events from specs: `t:Spearmint.Event.event_spec()`
    ```elixir
    Spearmint.event({Demo.Events.HeroMoved, [direction: :left]})
    ```

  > #### Note  {: .info}
  > There are many ways to filter events in the Systems by their struct like:
  >  ```elixir
  >  Enum.filter(events, &match?(%Demo.Events.MoveHero{direction: :right}, &1)) # this allows further pattern matching in the event struct
  >  # or
  >  Enum.filter(events, & &1.__struct__ == Demo.Events.MoveHero)
  >  # or
  >  Enum.filter(events, & fn %event_module{}  -> event_module == Demo.Events.MoveHero end)
  >  ```
  """

  @typedoc """
  An `event_spec` is the definition required to create an event.

  ## Examples
    ```elixir
    Demo.Events.MoveHero
    {Demo.Events.MoveHero, [direction: :left]}
    ```
  """
  @type event_spec ::
          (event_module :: module())
          | {event_module :: module(), event_fields :: keyword()}

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      Module.register_attribute(__MODULE__, :ecs_type, accumulate: false)
      Module.put_attribute(__MODULE__, :ecs_type, :event)

      fields = Keyword.get(opts, :fields, [])

      unless is_list(fields) do
        raise ArgumentError,
              "Invalid fields for Event: #{Kernel.inspect(__MODULE__)}. The `:fields` option must be a list with all the Event struct keys and their default values (if any). Eg: [:foo, :bar, baz: 1]"
      end

      defstruct fields

      @doc false
      def __ecs_type__ do
        @ecs_type
      end
    end
  end
end
