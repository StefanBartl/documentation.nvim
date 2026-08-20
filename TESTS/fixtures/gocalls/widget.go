// Package widgets is the fixture for Go call edges.
//
// Everything here is real, compiling Go on purpose. The resolver's hardest
// case — one name declared in two files of one directory — is only honest if
// the language actually permits it, and it does: `widgets` and `widgets_test`
// are two packages living in the same directory.
package widgets

// Use calls a function declared in a sibling *file* of the same package.
//
// This is the case the whole feature exists for: nothing at this call site
// says `double` lives in helper.go, and a file-scoped resolver finds nothing.
func Use(n int) int {
	return double(n)
}

// Local calls a function this file declares itself.
//
// Kept beside Use so the two orderings are one test: this file's own
// declaration must still win, and must not become ambiguous with the package
// index sitting behind it.
func Local(n int) int {
	return same(n)
}

func same(n int) int {
	return n
}

// Shaky calls a name two files in this directory declare.
//
// `shared` exists in helper.go (package widgets) and again in widget_test.go
// (package widgets_test). Real Go compiles both, which is exactly why the
// directory is not one scope and the edge cannot be guessed.
func Shaky() int {
	return shared()
}
