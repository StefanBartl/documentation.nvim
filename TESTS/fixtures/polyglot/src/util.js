/**
 * The JavaScript half.
 * @module src/util
 */

/**
 * Join two names.
 * @param {string} a first
 * @param {string} b second
 * @returns {string}
 */
export function polyglotFixtureJoin(a, b) {
  if (!a) return b;
  return a + "/" + b;
}
