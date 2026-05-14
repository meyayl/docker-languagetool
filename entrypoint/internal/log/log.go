// Package log provides coloured INFO/WARN/ERROR helpers for the entrypoint.
// It is imported under the alias "ilog" to avoid shadowing the standard library.
package log

import "fmt"

const (
	green  = "\033[0;32m"
	orange = "\033[0;33m"
	red    = "\033[0;31m"
	reset  = "\033[0m"
)

func Info(format string, args ...any) {
	fmt.Printf(green+"INFO"+reset+": "+format+"\n", args...)
}

func Warn(format string, args ...any) {
	fmt.Printf(orange+"WARN"+reset+": "+format+"\n", args...)
}

func Error(format string, args ...any) {
	fmt.Printf(red+"ERROR"+reset+": "+format+"\n", args...)
}

// Line prints a plain line with no prefix (used for separators and indented sub-lines).
func Line(format string, args ...any) {
	fmt.Printf(format+"\n", args...)
}
