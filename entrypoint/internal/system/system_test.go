package system

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

const testPasswd = `root:x:0:0:root:/root:/bin/sh
languagetool:x:783:783:Linux User,,,:/home/languagetool:/sbin/nologin
nobody:x:65534:65534:nobody:/:/sbin/nologin
`

const testGroup = `root:x:0:root
languagetool:x:783:
nobody:x:65534:
`

func writeTemp(t *testing.T, dir, name, content string) string {
	t.Helper()
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestLookupUserIn(t *testing.T) {
	dir := t.TempDir()
	p := writeTemp(t, dir, "passwd", testPasswd)

	u, err := lookupUserIn(p, "languagetool")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if u.UID != 783 || u.GID != 783 {
		t.Errorf("got uid=%d gid=%d, want 783:783", u.UID, u.GID)
	}
}

func TestLookupUserInNotFound(t *testing.T) {
	dir := t.TempDir()
	p := writeTemp(t, dir, "passwd", testPasswd)

	_, err := lookupUserIn(p, "ghost")
	if !errors.Is(err, ErrNotFound) {
		t.Errorf("expected ErrNotFound, got %v", err)
	}
}

func TestLookupGroupByGIDIn(t *testing.T) {
	dir := t.TempDir()
	p := writeTemp(t, dir, "group", testGroup)

	g, err := lookupGroupByGIDIn(p, 783)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if g.Name != "languagetool" {
		t.Errorf("got %q, want %q", g.Name, "languagetool")
	}
}

func TestLookupGroupByGIDInNotFound(t *testing.T) {
	dir := t.TempDir()
	p := writeTemp(t, dir, "group", testGroup)

	_, err := lookupGroupByGIDIn(p, 9999)
	if !errors.Is(err, ErrNotFound) {
		t.Errorf("expected ErrNotFound, got %v", err)
	}
}

func TestModifyPasswdFieldUID(t *testing.T) {
	lines := []string{
		"root:x:0:0:root:/root:/bin/sh",
		"languagetool:x:783:783:Linux User,,,:/home/languagetool:/sbin/nologin",
	}
	result, err := modifyPasswdField(lines, "languagetool", 2, "1001")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := "languagetool:x:1001:783:Linux User,,,:/home/languagetool:/sbin/nologin"
	if result[1] != want {
		t.Errorf("got %q, want %q", result[1], want)
	}
}

func TestModifyFileAtomicity(t *testing.T) {
	dir := t.TempDir()
	p := writeTemp(t, dir, "passwd", testPasswd)

	err := modifyFile(p, func(lines []string) ([]string, error) {
		return modifyPasswdField(lines, "languagetool", 2, "1001")
	})
	if err != nil {
		t.Fatalf("modifyFile error: %v", err)
	}

	u, err := lookupUserIn(p, "languagetool")
	if err != nil {
		t.Fatalf("lookup after modify: %v", err)
	}
	if u.UID != 1001 {
		t.Errorf("uid after modify: got %d, want 1001", u.UID)
	}
}

func TestModifyFilePreservesNewline(t *testing.T) {
	dir := t.TempDir()
	p := writeTemp(t, dir, "passwd", testPasswd)

	_ = modifyFile(p, func(lines []string) ([]string, error) {
		return lines, nil
	})

	data, _ := os.ReadFile(p)
	if len(data) == 0 || data[len(data)-1] != '\n' {
		t.Error("file should end with newline")
	}
}
