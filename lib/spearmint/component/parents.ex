# Forked from ECSpanse 0.10.1 https://github.com/iacobson/ecspanse/releases/tag/v0.10.1
# Modifications Copyright (C) 2026 Aaron Schmidlkofer

defmodule Spearmint.Component.Parents do
  @moduledoc """
  The `Parents` component is a special component provided by the framework
  to maintain references to an entity's parent entities.

  Dedicated queries and commands are provided to interact with this component.

  An empty `Parents` component is automatically added upon entity creation,
  even if no parent entities are defined at the time of creation.

  > #### Spearmint parent-child relationships are **bidirectional associations** {: .info}
  """
  use Spearmint.Component,
    state: [entities: []]

  @typedoc """
  Entity's parents list.
  """
  @type t :: %__MODULE__{
          entities: list(Spearmint.Entity.t())
        }
end
