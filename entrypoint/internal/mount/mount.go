package mount

import "syscall"

// IsROMount reports whether the root filesystem "/" is mounted read-only.
// It uses syscall.Statfs which sets ST_RDONLY (0x1) in Flags for ro mounts.
func IsROMount() (bool, error) {
	var stat syscall.Statfs_t
	if err := syscall.Statfs("/", &stat); err != nil {
		return false, err
	}
	return stat.Flags&0x1 != 0, nil
}
