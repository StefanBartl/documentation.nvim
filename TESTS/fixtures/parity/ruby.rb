require "other"

# Parity fixture — Ruby.
#
# One documented public method, one private helper, a require, a call,
# a module constant and a marker. `private` is a positional statement, so
# the helper below it is private and the one above it is not.
module Parity
  MAX = 10

  # Widen a value.
  #
  # @param n [Integer] How much.
  # @return [Integer] The widened value.
  def widen(n)
    # TODO: cap at MAX
    double(n) + Other.bump(MAX)
  end

  private

  # Double a value.
  #
  # @param n [Integer] How much.
  # @return [Integer] The doubled value.
  def double(n)
    n * 2
  end
end
