package logback

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/beevik/etree"
)

const sampleLogback = `<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <appender name="STDOUT" class="ch.qos.logback.core.ConsoleAppender">
    <encoder>
      <pattern>%d{HH:mm:ss.SSS} [%thread] %-5level %logger{36} - %msg%n</pattern>
    </encoder>
  </appender>
  <logger name="org.languagetool" level="INFO" additivity="false">
    <appender-ref ref="STDOUT"/>
  </logger>
  <root level="WARN">
    <appender-ref ref="STDOUT"/>
  </root>
</configuration>
`

func TestPatchLogLevel(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "logback.xml")
	dst := filepath.Join(dir, "logback_out.xml")

	if err := os.WriteFile(src, []byte(sampleLogback), 0644); err != nil {
		t.Fatal(err)
	}

	if err := PatchLogLevel(src, dst, "DEBUG"); err != nil {
		t.Fatalf("PatchLogLevel: %v", err)
	}

	doc := etree.NewDocument()
	if err := doc.ReadFromFile(dst); err != nil {
		t.Fatalf("parse output: %v", err)
	}

	root := doc.Root()
	for _, child := range root.ChildElements() {
		if child.Tag == "logger" && child.SelectAttrValue("name", "") == "org.languagetool" {
			level := child.SelectAttrValue("level", "")
			if level != "DEBUG" {
				t.Errorf("level: got %q, want %q", level, "DEBUG")
			}
			return
		}
	}
	t.Fatal("logger[@name='org.languagetool'] not found in output")
}

func TestPatchLogLevelPreservesOtherContent(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "logback.xml")
	dst := filepath.Join(dir, "logback_out.xml")

	if err := os.WriteFile(src, []byte(sampleLogback), 0644); err != nil {
		t.Fatal(err)
	}
	if err := PatchLogLevel(src, dst, "WARN"); err != nil {
		t.Fatal(err)
	}

	data, err := os.ReadFile(dst)
	if err != nil {
		t.Fatalf("read output: %v", err)
	}
	if !strings.Contains(string(data), "STDOUT") {
		t.Error("appender content should be preserved")
	}
}

func TestPatchLogLevelMissingLogger(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "logback.xml")
	dst := filepath.Join(dir, "logback_out.xml")

	noLogger := `<?xml version="1.0"?><configuration></configuration>`
	if err := os.WriteFile(src, []byte(noLogger), 0644); err != nil {
		t.Fatal(err)
	}

	err := PatchLogLevel(src, dst, "DEBUG")
	if err == nil {
		t.Fatal("expected error when logger element missing")
	}
}
