# Spearmint

Spearmint is an Entity Component System (ECS) library for Elixir
From its shameless root library ECSpanse, the code has been modified to bring:
 - Frame based simulation instead of time based simulation

The goal is to eventually support:
 - Parallel execution of multiple ECS simulations in a single BEAM instance

These changes are expected to drastically impact the ergonomics of the library in a negative way.
Mainly, all of the conveniences afforded by using global ets tables and singletons are lost.
For my use case, that is a trade I am willing to take. 

If you want a well written and more ergonomic ECS ecosystem, please check out ECSpanse. https://hex.pm/packages/ecspanse
This fork has been made without any direct communication with the ECSpanse team and my recommendation of their library does not imply any form of recommendation or endorsement of this fork on their behalf.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `spearmint` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:spearmint, "~> 0.0.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/spearmint>.
