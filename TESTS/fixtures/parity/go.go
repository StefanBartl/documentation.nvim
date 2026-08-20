// Package parity is the parity fixture for Go.
//
// One documented exported function, one unexported helper, an import, a
// call, a package constant and a marker.
package parity

import "github.com/acme/other"

// Max is how many.
const Max = 10

// double doubles a value.
func double(n int) int {
	return n * 2
}

// Widen widens a value.
func Widen(n int) (int, error) {
	// TODO: cap at Max
	return double(n) + other.Bump(Max), nil
}
