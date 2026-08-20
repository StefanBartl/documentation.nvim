// Parity fixture — Dart. The file's summary is the first type's `///` block:
// a file of only top-level functions has none. See docs/LANGUAGES.md.
library parity;

import 'other.dart';

const int max = 10;

/// Parity fixture — Dart.
///
/// One documented public method, one private helper, an import, a call,
/// a library constant and a marker.
class Widget {
  /// Double a value.
  ///
  /// [n] is how much. Returns the doubled value.
  int _double(int n) {
    return n * 2;
  }

  /// Widen a value.
  ///
  /// [n] is how much. Returns the widened value.
  int widen(int n) {
    // TODO: cap at max
    return _double(n) + bump(max);
  }
}
