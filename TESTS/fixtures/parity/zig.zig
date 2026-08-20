//! Parity fixture — Zig.
//!
//! One documented public function, one private helper, an import, a call,
//! a module-level constant and a marker.

const other = @import("other.zig");

pub const MAX: i32 = 10;

/// Double a value.
fn double(n: i32) i32 {
    return n * 2;
}

/// Widen a value.
pub fn widen(n: i32) i32 {
    // TODO: cap at MAX
    return double(n) + other.bump(MAX);
}
