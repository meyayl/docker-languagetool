// Package ownership fixes file and directory ownership on volume mounts so
// they are writable by the mapped UID/GID before the privilege drop.
package ownership

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"syscall"

	ilog "github.com/meyayl/docker-languagetool/internal/log"
)

// FixDirOwnership walks path and chowns any entry not already owned by uid:gid.
// If path is not accessible it logs a warning and returns nil (non-fatal).
func FixDirOwnership(path string, uid, gid uint32) error {
	info, err := os.Stat(path)
	if err != nil {
		ilog.Warn("permissions on %q do not allow to fix ownership.\n      "+
			"If this is intentional, please set environment variable DISABLE_PERMISSION_FIX to true to disable this feature.", path)
		return nil
	}
	if !info.IsDir() {
		return fmt.Errorf("%q is not a directory", path)
	}

	return filepath.WalkDir(path, func(p string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return nil // skip inaccessible entries, matching find -exec behavior
		}
		fi, err := d.Info()
		if err != nil {
			return nil
		}
		stat, ok := fi.Sys().(*syscall.Stat_t)
		if !ok {
			return nil
		}
		if stat.Uid != uid || stat.Gid != gid {
			if err := os.Lchown(p, int(uid), int(gid)); err != nil {
				ilog.Warn("chown %q: %v", p, err)
			}
		}
		return nil
	})
}

// FixOwnership calls FixDirOwnership on the ngram model directory and the
// parent directory of the fasttext model path, when those vars are non-empty.
func FixOwnership(languageModelDir, fasttextModelPath string, uid, gid uint32) error {
	if languageModelDir != "" {
		ilog.Info("Fixing ownership for ngrams base folder if necessary.")
		if err := FixDirOwnership(languageModelDir, uid, gid); err != nil {
			return err
		}
	}
	if fasttextModelPath != "" {
		ilog.Info("Fixing ownership for fasttext model file if necessary.")
		parent := filepath.Dir(fasttextModelPath)
		if err := FixDirOwnership(parent, uid, gid); err != nil {
			return err
		}
	}
	return nil
}
