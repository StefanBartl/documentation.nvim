// Parity fixture — Java. The file's summary is the first type's Javadoc,
// because Java has no file-level doc comment; see docs/LANGUAGES.md.
package parity;

import parity.Other;

/**
 * Parity fixture — Java.
 *
 * One documented public method, one private helper, an import, a call,
 * a class constant and a marker.
 */
public class Java {
    public static final int MAX = 10;

    /**
     * Double a value.
     *
     * @param n how much
     * @return the doubled value
     */
    private static int double_(int n) {
        return n * 2;
    }

    /**
     * Widen a value.
     *
     * @param n how much
     * @return the widened value
     */
    public static int widen(int n) {
        // TODO: cap at MAX
        return double_(n) + Other.bump(MAX);
    }
}
