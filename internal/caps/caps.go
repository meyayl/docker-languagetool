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
	CAP_CHOWN        = 0
	CAP_DAC_OVERRIDE = 1
	CAP_SETUID       = 6
	CAP_SETGID       = 7
)

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
	return caps&(1<<uint(bit)) != 0, nil
}

// PrintCapabilities writes a 4-line capability status table to w matching
// the original shell script format.
func PrintCapabilities(w io.Writer) error {
	type entry struct {
		bit  int
		name string
		desc string
	}
	entries := []entry{
		{CAP_CHOWN, "CAP_CHOWN", "Can change owner of files and directories"},
		{CAP_DAC_OVERRIDE, "CAP_DAC_OVERRIDE", "Can bypass file permission checks when changing owner"},
		{CAP_SETUID, "CAP_SETUID", "Can execute languagetool with arbitrary uid"},
		{CAP_SETGID, "CAP_SETGUID", "Can execute languagetool with arbitrary gid"},
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
