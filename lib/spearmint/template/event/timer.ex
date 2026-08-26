# Forked from ECSpanse 0.10.1 https://github.com/iacobson/ecspanse/releases/tag/v0.10.1
# Modifications Copyright (C) 2026 Aaron Schmidlkofer

defmodule Spearmint.Template.Event.Timer do
  @moduledoc """
  The `Timer` is a **Template Event** designed to facilitate the creation
  of custom timer (countdown) events.

  It serves as a foundation for building custom timer events with `use Spearmint.Template.Event.Timer`.
  It takes no options.

  The event that will be dispatched by `Event.System.Timer` system when
  the timer component reaches 0.

  Their state is predefined to `%CustomEventModule{entity_id: entity_id}`,
  where entity refers to owner of the custom timer component.

  ## Example:
    ```elixir
    defmodule EnergyRestoreTimer do
      use Spearmint.Template.Event.Timer
    end
    ```

  See `Spearmint.Template.Component.Timer` for more details.
  """
  use Spearmint.Template.Event, fields: [:entity_id]
end
