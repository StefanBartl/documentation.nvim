<?php
// Parity fixture — PHP. The file's summary is the first type's docblock,
// because PHP has no file-level doc block; see docs/LANGUAGES.md.

namespace Parity;

use Parity\Other;

/**
 * Parity fixture — PHP.
 *
 * One documented public method, one private helper, a use, a call,
 * a class constant and a marker.
 */
class Widget
{
    public const MAX = 10;

    /**
     * Double a value.
     *
     * @param int $n How much.
     * @return int The doubled value.
     */
    private static function doubleIt(int $n): int
    {
        return $n * 2;
    }

    /**
     * Widen a value.
     *
     * @param int $n How much.
     * @return int The widened value.
     */
    public static function widen(int $n): int
    {
        // TODO: cap at MAX
        return self::doubleIt($n) + Other::bump(self::MAX);
    }
}
