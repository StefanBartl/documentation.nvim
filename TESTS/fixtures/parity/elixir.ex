defmodule Parity.Widget do
  @moduledoc """
  Parity fixture — Elixir.

  One documented public function, one private helper, an alias, a call,
  a module attribute and a marker.
  """

  alias Parity.Other

  @max 10

  @doc """
  Widen a value.
  """
  @spec widen(integer()) :: integer()
  def widen(n) do
    # TODO: cap at @max
    double(n) + Other.bump(@max)
  end

  @doc """
  Double a value.
  """
  @spec double(integer()) :: integer()
  defp double(n), do: n * 2
end
