// Parity fixture — C#.
//
// One documented public method, one private helper, a using, a call,
// a class constant and a marker.

using Parity.Other;

namespace Parity
{
    /// <summary>Parity fixture.</summary>
    public class Widget
    {
        public const int Max = 10;

        /// <summary>Double a value.</summary>
        /// <param name="n">How much.</param>
        /// <returns>The doubled value.</returns>
        private static int Double(int n)
        {
            return n * 2;
        }

        /// <summary>Widen a value.</summary>
        /// <param name="n">How much.</param>
        /// <returns>The widened value.</returns>
        public static int Widen(int n)
        {
            // TODO: cap at Max
            return Double(n) + Other.Bump(Max);
        }
    }
}
