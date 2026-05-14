// Package mount detects whether the container root filesystem is read-only.
package mount

import "syscall"

// stRdonly is the ST_RDONLY flag from <sys/statfs.h>; set in Statfs_t.Flags
// when the filesystem is mounted read-only.
const stRdonly = 0x1

// IsROMount reports whether the root filesystem "/" is mounted read-only.
func IsROMount() (bool, error) {
	var stat syscall.Statfs_t
	if err := syscall.Statfs("/", &stat); err != nil {
		return false, err
	}
	return stat.Flags&stRdonly != 0, nil
}
