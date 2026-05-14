package mount

import (
	"io"
	"os"
	"strings"
)

// IsROMount reports whether the root filesystem "/" is mounted read-only
// by parsing /proc/mounts.
func IsROMount() (bool, error) {
	f, err := os.Open("/proc/mounts")
	if err != nil {
		return false, err
	}
	defer f.Close()
	return parseROMount(f)
}

func parseROMount(r io.Reader) (bool, error) {
	data, err := io.ReadAll(r)
	if err != nil {
		return false, err
	}

	for _, line := range strings.Split(string(data), "\n") {
		if line == "" {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 4 {
			continue
		}
		device, mountpoint, options := fields[0], fields[1], fields[3]
		if device == "rootfs" || mountpoint != "/" {
			continue
		}
		for _, opt := range strings.Split(options, ",") {
			if opt == "ro" {
				return true, nil
			}
			if opt == "rw" {
				return false, nil
			}
		}
	}
	return false, nil
}
