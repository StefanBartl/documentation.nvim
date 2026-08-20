// Parity fixture — Scala. The file's summary is the first type's Scaladoc,
// not a top-level val's; see docs/LANGUAGES.md.
package parity

import parity.Other.bump

/**
 * Parity fixture — Scala.
 *
 * One documented public method, one private helper, an import, a call,
 * an object constant and a marker.
 */
object Widget {
  val MAX = 10

  /**
   * Double a value.
   *
   * @param n How much.
   * @return The doubled value.
   */
  private def double(n: Int): Int = n * 2

  /**
   * Widen a value.
   *
   * @param n How much.
   * @return The widened value.
   */
  def widen(n: Int): Int = {
    // TODO: cap at MAX
    double(n) + bump(MAX)
  }
}
