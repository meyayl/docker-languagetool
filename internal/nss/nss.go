package nss

import (
	"fmt"
	"os"
)

// SetupNSSWrapper creates nss_wrapper temp files for the given uid/gid,
// sets LD_PRELOAD, NSS_WRAPPER_PASSWD, and NSS_WRAPPER_GROUP, and makes
// both files world-readable. This allows user identity override on
// read-only root filesystems where /etc/passwd cannot be modified.
func SetupNSSWrapper(uid, gid uint32) error {
	passwdFile, err := os.CreateTemp("", "nss_wrapper_passwd_*")
	if err != nil {
		return fmt.Errorf("create nss passwd temp: %w", err)
	}
	passwdPath := passwdFile.Name()

	groupFile, err := os.CreateTemp("", "nss_wrapper_group_*")
	if err != nil {
		passwdFile.Close()
		os.Remove(passwdPath)
		return fmt.Errorf("create nss group temp: %w", err)
	}
	groupPath := groupFile.Name()

	passwdLine := fmt.Sprintf("languagetool:x:%d:%d:languagetool gecos:/home/languagetool:/sbin/nologin\n", uid, gid)
	groupLine := fmt.Sprintf("languagetool:x:%d:\n", gid)

	if _, err := fmt.Fprint(passwdFile, passwdLine); err != nil {
		passwdFile.Close()
		groupFile.Close()
		os.Remove(passwdPath)
		os.Remove(groupPath)
		return fmt.Errorf("write nss passwd: %w", err)
	}
	if _, err := fmt.Fprint(groupFile, groupLine); err != nil {
		passwdFile.Close()
		groupFile.Close()
		os.Remove(passwdPath)
		os.Remove(groupPath)
		return fmt.Errorf("write nss group: %w", err)
	}

	passwdFile.Close()
	groupFile.Close()

	if err := os.Chmod(passwdPath, 0444); err != nil {
		return fmt.Errorf("chmod nss passwd: %w", err)
	}
	if err := os.Chmod(groupPath, 0444); err != nil {
		return fmt.Errorf("chmod nss group: %w", err)
	}

	os.Setenv("LD_PRELOAD", "/usr/lib/libnss_wrapper.so")
	os.Setenv("NSS_WRAPPER_PASSWD", passwdPath)
	os.Setenv("NSS_WRAPPER_GROUP", groupPath)

	return nil
}
