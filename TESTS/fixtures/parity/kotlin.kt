/**
 * Parity fixture — Kotlin.
 *
 * One documented public function, one private helper, an import, a call,
 * a file constant and a marker.
 */
package parity

import parity.other.bump

const val MAX = 10

/**
 * Double a value.
 *
 * @param n How much.
 * @return The doubled value.
 */
private fun double(n: Int): Int {
    return n * 2
}

/**
 * Widen a value.
 *
 * @param n How much.
 * @return The widened value.
 */
fun widen(n: Int): Int {
    // TODO: cap at MAX
    return double(n) + bump(MAX)
}
