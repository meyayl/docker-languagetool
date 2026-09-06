// Package config writes LanguageTool's config.properties from langtool_* env vars.
package config

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	ilog "github.com/meyayl/docker-languagetool/internal/log"
)

// WriteConfigProperties iterates os.Environ(), collects all variables whose
// names start with "langtool_", strips the prefix, and writes KEY=VALUE pairs
// to path. It truncates the file if it already exists.
//
// The "languageModel" key is omitted when its target directory is missing or
// empty: LanguageTool's HTTP server silently disables spelling rules for a
// language when languageModel points at a directory without a usable ngram
// model for it, so the key must not be written unless the directory actually
// contains data (e.g. pre-downloaded ngram models mounted by the user).
//
// Returns true if at least one entry was written.
func WriteConfigProperties(path string) (bool, error) {
	ilog.Info("Creating new LanguageTool config file.")

	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0644)
	if err != nil {
		return false, fmt.Errorf("open %s: %w", path, err)
	}
	defer f.Close()

	skipLanguageModel := isEmptyDir(os.Getenv("langtool_languageModel"))

	written := false
	for _, env := range os.Environ() {
		idx := strings.IndexByte(env, '=')
		if idx < 0 {
			continue
		}
		name, value := env[:idx], env[idx+1:]
		if !strings.HasPrefix(name, "langtool_") {
			continue
		}
		key := strings.TrimPrefix(name, "langtool_")
		if key == "languageModel" && skipLanguageModel {
			continue
		}
		if _, err := fmt.Fprintf(f, "%s=%s\n", key, value); err != nil {
			return written, fmt.Errorf("write config: %w", err)
		}
		written = true
	}
	return written, nil
}

// isEmptyDir reports whether dir is unset, does not exist, or contains no entries.
func isEmptyDir(dir string) bool {
	if dir == "" {
		return true
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return true
	}
	return len(entries) == 0
}

// PrintConfig prints the contents of path to stdout, each line indented by 2 spaces.
func PrintConfig(path string) error {
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open %s: %w", path, err)
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		fmt.Printf("  %s\n", scanner.Text())
	}
	return scanner.Err()
}
