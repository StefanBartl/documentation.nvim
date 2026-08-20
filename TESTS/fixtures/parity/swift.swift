/// Parity fixture — Swift.
///
/// One documented public function, one private helper, an import, a call,
/// a file constant and a marker.

import Other

let MAX = 10

/// Double a value.
///
/// - Parameter n: How much.
/// - Returns: The doubled value.
private func double(_ n: Int) -> Int {
    return n * 2
}

/// Widen a value.
///
/// - Parameter n: How much.
/// - Returns: The widened value.
public func widen(_ n: Int) -> Int {
    // TODO: cap at MAX
    return double(n) + bump(MAX)
}
