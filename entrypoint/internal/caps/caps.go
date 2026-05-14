// Package caps reads and queries Linux process capabilities from /proc/self/status.
package caps

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

const (
	CapChown       = 0
	CapDACOverride = 1
	CapSetUID      = 6
	CapSetGID      = 7
)

type capEntry struct {
	bit  int
	name string
	desc string
}

// ReadPermitted reads the CapPrm bitmask from /proc/self/status.
func ReadPermitted() (uint64, error) {
	f, err := os.Open("/proc/self/status")
	if err != nil {
		return 0, err
	}
	defer f.Close()
	return readPermittedFrom(f)
}

func readPermittedFrom(r io.Reader) (uint64, error) {
	scanner := bufio.NewScanner(r)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "CapPrm:") {
			hex := strings.TrimSpace(strings.TrimPrefix(line, "CapPrm:"))
			val, err := strconv.ParseUint(hex, 16, 64)
			if err != nil {
				return 0, fmt.Errorf("parse CapPrm %q: %w", hex, err)
			}
			return val, nil
		}
	}
	return 0, fmt.Errorf("CapPrm not found in /proc/self/status")
}

// IsEnabled reports whether the capability at the given bit position is set.
func IsEnabled(bit int) (bool, error) {
	caps, err := ReadPermitted()
	if err != nil {
		return false, err
	}
	return caps&(1<<uint(bit)) != 0, nil //nolint:gosec
}

// PrintCapabilities writes a 4-line capability status table to w matching
// the original shell script format.
func PrintCapabilities(w io.Writer) error {
	entries := []capEntry{
		{CapChown, "CAP_CHOWN", "Can change owner of files and directories"},
		{CapDACOverride, "CAP_DAC_OVERRIDE", "Can bypass file permission checks when changing owner"},
		{CapSetUID, "CAP_SETUID", "Can execute languagetool with arbitrary uid"},
		{CapSetGID, "CAP_SETGID", "Can execute languagetool with arbitrary gid"},
	}

	const (
		colorGreen = "\033[0;32m"
		colorRed   = "\033[0;31m"
		colorReset = "\033[0m"
	)

	for _, e := range entries {
		enabled, err := IsEnabled(e.bit)
		if err != nil {
			return err
		}
		status := colorGreen + "yes" + colorReset
		if !enabled {
			status = colorRed + "no" + colorReset
		}
		fmt.Fprintf(w, "  %-18s%s: %s\n", e.name, e.desc, status)
	}
	return nil
}
