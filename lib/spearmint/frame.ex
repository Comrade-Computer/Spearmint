# Forked from ECSpanse 0.10.1 https://github.com/iacobson/ecspanse/releases/tag/v0.10.1
# Modifications Copyright (C) 2026 Aaron Schmidlkofer

defmodule Spearmint.Frame do
  @moduledoc """
  Heavily based on the fantastic ECSpanse library

  The frame is a struct that encapsulates the state of the current frame.

  It holds information such as the time elapsed since the last frame and any batches of events that have been inserted during the previous frame.
  This frame struct is available to all systems during the frame.

  ## Fields

  - `:event_batches` - a collection of event batches queued for execution within this frame.
  """

  @typedoc """
  The frame struct.

  ## Example

    ```elixir
    %Spearmint.Frame{
      event_batches: [[%Demo.Events.MoveHero{direction: :left}, %Demo.Events.FindResource{type: :gold}], [%Demo.Events.MoveHero{direction: :down}]],
    }
    ```

  """
  @type t :: %__MODULE__{
          event_batches: list(list(event :: struct()))
        }

  defstruct event_batches: []
end
