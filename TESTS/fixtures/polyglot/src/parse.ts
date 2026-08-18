/**
 * The TypeScript half.
 * @module src/parse
 */
import { polyglotFixtureJoin } from "./util.js";

/**
 * Split a path.
 * @param p the path
 */
export async function polyglotFixtureSplit(p: string): Promise<string[]> {
  const parts = p.split("/");
  return parts.length ? parts : [polyglotFixtureJoin("a", "b")];
}
