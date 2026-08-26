# Forked from ECSpanse 0.10.1 https://github.com/iacobson/ecspanse/releases/tag/v0.10.1
# Modifications Copyright (C) 2026 Aaron Schmidlkofer

defmodule Spearmint.Event.StateTransition do
  @moduledoc """
  Special library event emitted upon a state change.

  ## Examples

    ```elixir
    %Spearmint.Event.StateTransition{
      module: Demo.States.Game,
      previous_state: :running,
      current_state: :paused
    }
    ```
  """

  use Spearmint.Event, fields: [:module, :previous_state, :current_state]

  @type t :: %__MODULE__{
          module: module(),
          previous_state: atom(),
          current_state: atom()
        }
end
