// Package system provides atomic modification of /etc/passwd and /etc/group
// to remap the languagetool user/group UID and GID at container startup.
package system

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	ilog "github.com/meyayl/docker-languagetool/internal/log"
)

var ErrNotFound = errors.New("not found")

// UserInfo holds parsed /etc/passwd fields for a single user.
type UserInfo struct {
	Name     string
	Password string
	UID      uint32
	GID      uint32
	GECOS    string
	Home     string
	Shell    string
}

// GroupInfo holds parsed /etc/group fields for a single group.
type GroupInfo struct {
	Name     string
	Password string
	GID      uint32
	Members  string
}

// LookupUser finds a user by name in /etc/passwd.
func LookupUser(name string) (UserInfo, error) {
	return lookupUserIn("/etc/passwd", name)
}

func lookupUserIn(path, name string) (UserInfo, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return UserInfo{}, fmt.Errorf("read %s: %w", path, err)
	}
	for _, line := range strings.Split(string(data), "\n") {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.SplitN(line, ":", 7)
		if len(fields) < 7 || fields[0] != name {
			continue
		}
		uid, _ := strconv.ParseUint(fields[2], 10, 32)
		gid, _ := strconv.ParseUint(fields[3], 10, 32)
		return UserInfo{
			Name:     fields[0],
			Password: fields[1],
			UID:      uint32(uid),
			GID:      uint32(gid),
			GECOS:    fields[4],
			Home:     fields[5],
			Shell:    fields[6],
		}, nil
	}
	return UserInfo{}, fmt.Errorf("user %q: %w", name, ErrNotFound)
}

// LookupGroupByGID finds a group by GID in /etc/group.
func LookupGroupByGID(gid uint32) (GroupInfo, error) {
	return lookupGroupByGIDIn("/etc/group", gid)
}

func lookupGroupByGIDIn(path string, gid uint32) (GroupInfo, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return GroupInfo{}, fmt.Errorf("read %s: %w", path, err)
	}
	for _, line := range strings.Split(string(data), "\n") {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.SplitN(line, ":", 4)
		if len(fields) < 4 {
			continue
		}
		g, _ := strconv.ParseUint(fields[2], 10, 32)
		if uint32(g) == gid {
			return GroupInfo{
				Name:     fields[0],
				Password: fields[1],
				GID:      uint32(g),
				Members:  fields[3],
			}, nil
		}
	}
	return GroupInfo{}, fmt.Errorf("group with gid %d: %w", gid, ErrNotFound)
}

// SetUserUID changes the UID for username in /etc/passwd atomically.
func SetUserUID(username string, newUID uint32) error {
	return modifyFile("/etc/passwd", func(lines []string) ([]string, error) {
		return modifyPasswdField(lines, username, 2, strconv.FormatUint(uint64(newUID), 10))
	})
}

// SetUserGID changes the primary GID for username in /etc/passwd atomically.
func SetUserGID(username string, newGID uint32) error {
	return modifyFile("/etc/passwd", func(lines []string) ([]string, error) {
		return modifyPasswdField(lines, username, 3, strconv.FormatUint(uint64(newGID), 10))
	})
}

// SetGroupGID changes the GID for groupname in /etc/group atomically.
func SetGroupGID(groupname string, newGID uint32) error {
	return modifyFile("/etc/group", func(lines []string) ([]string, error) {
		found := false
		for i, line := range lines {
			if line == "" || strings.HasPrefix(line, "#") {
				continue
			}
			fields := strings.SplitN(line, ":", 4)
			if len(fields) < 4 || fields[0] != groupname {
				continue
			}
			fields[2] = strconv.FormatUint(uint64(newGID), 10)
			lines[i] = strings.Join(fields, ":")
			found = true
			break
		}
		if !found {
			return nil, fmt.Errorf("group %q: %w", groupname, ErrNotFound)
		}
		return lines, nil
	})
}

// UpdateUserMapping applies MAP_UID and MAP_GID changes to the "languagetool" user,
// replicating the shell script's user_map function exactly.
func UpdateUserMapping(mapUID uint32, mapUIDSet bool, mapGID uint32, mapGIDSet bool) error {
	if mapUIDSet {
		u, err := LookupUser("languagetool")
		if err != nil {
			return fmt.Errorf("lookup languagetool: %w", err)
		}
		if u.UID != mapUID {
			ilog.Info("Setting uid for user \"languagetool\" to %d.", mapUID)
			if err := SetUserUID("languagetool", mapUID); err != nil {
				return fmt.Errorf("set uid: %w", err)
			}
		}
	}

	if mapGIDSet {
		u, err := LookupUser("languagetool")
		if err != nil {
			return fmt.Errorf("lookup languagetool: %w", err)
		}
		if u.GID != mapGID {
			if existing, err := LookupGroupByGID(mapGID); err == nil {
				ilog.Info("Group %q already exists with gid %d.", existing.Name, mapGID)
				ilog.Info("Setting primary gid for user \"languagetool\" from %d to %d.", u.GID, mapGID)
				if err := SetUserGID("languagetool", mapGID); err != nil {
					return fmt.Errorf("set user gid: %w", err)
				}
			} else {
				ilog.Info("Changing gid of group \"languagetool\" to gid %d.", mapGID)
				if err := SetGroupGID("languagetool", mapGID); err != nil {
					return fmt.Errorf("set group gid: %w", err)
				}
			}
		}
	}

	return nil
}

func modifyPasswdField(lines []string, username string, fieldIdx int, value string) ([]string, error) {
	found := false
	for i, line := range lines {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		fields := strings.SplitN(line, ":", 7)
		if len(fields) < 7 || fields[0] != username {
			continue
		}
		fields[fieldIdx] = value
		lines[i] = strings.Join(fields, ":")
		found = true
		break
	}
	if !found {
		return nil, fmt.Errorf("user %q: %w", username, ErrNotFound)
	}
	return lines, nil
}

func modifyFile(path string, modify func([]string) ([]string, error)) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read %s: %w", path, err)
	}

	content := string(data)
	endsWithNewline := strings.HasSuffix(content, "\n")
	lines := strings.Split(strings.TrimRight(content, "\n"), "\n")

	modified, err := modify(lines)
	if err != nil {
		return err
	}

	result := strings.Join(modified, "\n")
	if endsWithNewline {
		result += "\n"
	}

	dir := filepath.Dir(path)
	info, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("stat %s: %w", path, err)
	}

	tmp, err := os.CreateTemp(dir, ".lt_tmp_*")
	if err != nil {
		return fmt.Errorf("create temp file: %w", err)
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)

	if err := tmp.Chmod(info.Mode()); err != nil {
		tmp.Close()
		return fmt.Errorf("chmod temp file: %w", err)
	}
	if _, err := fmt.Fprint(tmp, result); err != nil {
		tmp.Close()
		return fmt.Errorf("write temp file: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("close temp file: %w", err)
	}
	if err := os.Rename(tmpName, path); err != nil {
		return fmt.Errorf("rename %s → %s: %w", tmpName, path, err)
	}
	return nil
}
