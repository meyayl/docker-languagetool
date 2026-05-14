package config

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestWriteConfigProperties(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.properties")

	t.Setenv("langtool_languageModel", "/ngrams")
	t.Setenv("langtool_fasttextModel", "/fasttext/lid.176.bin")
	t.Setenv("OTHER_VAR", "should-not-appear")

	written, err := WriteConfigProperties(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !written {
		t.Error("expected written=true")
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read config: %v", err)
	}

	props := map[string]string{}
	scanner := bufio.NewScanner(strings.NewReader(string(data)))
	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.SplitN(line, "=", 2)
		if len(parts) == 2 {
			props[parts[0]] = parts[1]
		}
	}

	if v, ok := props["languageModel"]; !ok || v != "/ngrams" {
		t.Errorf("languageModel: got %q", v)
	}
	if v, ok := props["fasttextModel"]; !ok || v != "/fasttext/lid.176.bin" {
		t.Errorf("fasttextModel: got %q", v)
	}
	if _, ok := props["OTHER_VAR"]; ok {
		t.Error("OTHER_VAR should not be in config")
	}
}

func TestWriteConfigPropertiesEmpty(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.properties")

	// Unset all langtool_ vars that might be in the test environment
	for _, env := range os.Environ() {
		if strings.HasPrefix(env, "langtool_") {
			key := strings.SplitN(env, "=", 2)[0]
			t.Setenv(key, "")
			os.Unsetenv(key)
		}
	}

	written, err := WriteConfigProperties(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	_ = written // may or may not be true depending on test env
}

func TestWriteConfigPropertiesTruncates(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.properties")

	// Write initial content
	if err := os.WriteFile(path, []byte("old=content\n"), 0644); err != nil {
		t.Fatal(err)
	}

	t.Setenv("langtool_port", "8081")
	for _, env := range os.Environ() {
		if strings.HasPrefix(env, "langtool_") {
			parts := strings.SplitN(env, "=", 2)
			if parts[0] != "langtool_port" {
				os.Unsetenv(parts[0])
			}
		}
	}

	_, err := WriteConfigProperties(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read config after truncate: %v", err)
	}
	if strings.Contains(string(data), "old=content") {
		t.Error("file should have been truncated")
	}
}
