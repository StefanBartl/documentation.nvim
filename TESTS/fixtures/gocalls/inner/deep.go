// Package inner is a *different* package, because in Go a directory is the
// package boundary. Its own `double` must be the one Deep resolves to.
package inner

// Deep calls a sibling file inside this directory, not the one above it.
func Deep(n int) int {
	return double(n)
}
