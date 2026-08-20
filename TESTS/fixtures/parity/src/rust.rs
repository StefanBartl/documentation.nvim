//! Parity fixture — Rust.
//!
//! One documented public function, one private helper, a use, a call,
//! a module constant and a marker.

use other::bump;

/// How many.
pub const MAX: i32 = 10;

/// Double a value.
///
/// # Arguments
///
/// * `n` - How much.
///
/// # Returns
///
/// The doubled value.
fn double(n: i32) -> i32 {
    n * 2
}

/// Widen a value.
///
/// # Arguments
///
/// * `n` - How much.
///
/// # Returns
///
/// The widened value.
pub fn widen(n: i32) -> i32 {
    // TODO: cap at MAX
    double(n) + bump(MAX)
}
