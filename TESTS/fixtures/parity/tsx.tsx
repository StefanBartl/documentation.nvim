/**
 * @module parity/tsx
 * Parity fixture — TSX.
 */

import { bump } from "./other";

const MAX = 10;

/**
 * Widen a value.
 * @param n How much.
 * @returns widened
 */
export function widen(n: number): number {
  // TODO: cap at MAX
  return bump(n) + MAX;
}

/**
 * @internal
 * @param n
 * @returns doubled
 */
function double(n: number): number {
  return n * 2;
}
