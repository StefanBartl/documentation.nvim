/**
 * @module parity/js
 * Parity fixture — JavaScript.
 */

const other = require("./other");

const MAX = 10;

/**
 * Widen a value.
 * @param {number} n How much.
 * @returns {number} widened
 */
function widen(n) {
  // TODO: cap at MAX
  return other.bump(n) + MAX;
}

/**
 * @internal
 * @param {number} n
 * @returns {number}
 */
function double(n) {
  return n * 2;
}

module.exports = { widen, double };
