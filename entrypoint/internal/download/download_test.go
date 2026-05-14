package download

import (
	"archive/zip"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestIsValidZip(t *testing.T) {
	dir := t.TempDir()

	// Create a valid zip
	validPath := filepath.Join(dir, "valid.zip")
	w, err := os.Create(validPath)
	if err != nil {
		t.Fatalf("create valid zip: %v", err)
	}
	zw := zip.NewWriter(w)
	f, err := zw.Create("test.txt")
	if err != nil {
		t.Fatalf("zip create entry: %v", err)
	}
	if _, err := f.Write([]byte("hello")); err != nil {
		t.Fatalf("zip write: %v", err)
	}
	if err := zw.Close(); err != nil {
		t.Fatalf("zip close: %v", err)
	}
	if err := w.Close(); err != nil {
		t.Fatalf("file close: %v", err)
	}

	if !isValidZip(validPath) {
		t.Error("expected valid zip to return true")
	}

	// Truncated / corrupt zip
	invalidPath := filepath.Join(dir, "invalid.zip")
	os.WriteFile(invalidPath, []byte("not a zip"), 0644)
	if isValidZip(invalidPath) {
		t.Error("expected corrupt zip to return false")
	}

	// Non-existent
	if isValidZip(filepath.Join(dir, "nosuchfile.zip")) {
		t.Error("expected missing file to return false")
	}
}

func TestExtractZip(t *testing.T) {
	dir := t.TempDir()
	zipPath := filepath.Join(dir, "test.zip")
	destDir := filepath.Join(dir, "out")
	os.MkdirAll(destDir, 0755)

	// Build a zip with a file and a directory entry
	w, err := os.Create(zipPath)
	if err != nil {
		t.Fatalf("create zip: %v", err)
	}
	zw := zip.NewWriter(w)
	dh := &zip.FileHeader{Name: "subdir/"}
	dh.SetMode(0755 | os.ModeDir)
	if _, err := zw.CreateHeader(dh); err != nil {
		t.Fatalf("zip create dir header: %v", err)
	}
	f, err := zw.Create("subdir/hello.txt")
	if err != nil {
		t.Fatalf("zip create entry: %v", err)
	}
	if _, err := f.Write([]byte("hello world")); err != nil {
		t.Fatalf("zip write: %v", err)
	}
	if err := zw.Close(); err != nil {
		t.Fatalf("zip close: %v", err)
	}
	if err := w.Close(); err != nil {
		t.Fatalf("file close: %v", err)
	}

	if err := extractZip(zipPath, destDir); err != nil {
		t.Fatalf("extractZip: %v", err)
	}

	content, err := os.ReadFile(filepath.Join(destDir, "subdir", "hello.txt"))
	if err != nil {
		t.Fatalf("read extracted file: %v", err)
	}
	if string(content) != "hello world" {
		t.Errorf("got %q, want %q", string(content), "hello world")
	}
}

func TestExtractZipPathTraversal(t *testing.T) {
	dir := t.TempDir()
	zipPath := filepath.Join(dir, "evil.zip")
	destDir := filepath.Join(dir, "out")
	os.MkdirAll(destDir, 0755)

	// Build a zip with a path-traversal entry
	w, err := os.Create(zipPath)
	if err != nil {
		t.Fatalf("create zip: %v", err)
	}
	zw := zip.NewWriter(w)
	f, err := zw.Create("../evil.txt")
	if err != nil {
		t.Fatalf("zip create entry: %v", err)
	}
	if _, err := f.Write([]byte("pwned")); err != nil {
		t.Fatalf("zip write: %v", err)
	}
	if err := zw.Close(); err != nil {
		t.Fatalf("zip close: %v", err)
	}
	if err := w.Close(); err != nil {
		t.Fatalf("file close: %v", err)
	}

	if err := extractZip(zipPath, destDir); err == nil {
		t.Fatal("expected error for path traversal")
	}
}

func TestDownloadFile(t *testing.T) {
	body := []byte("test content")
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write(body)
	}))
	defer srv.Close()

	dir := t.TempDir()
	dest := filepath.Join(dir, "downloaded.bin")

	if err := downloadFile(srv.URL+"/test", dest); err != nil {
		t.Fatalf("downloadFile: %v", err)
	}

	got, _ := os.ReadFile(dest)
	if string(got) != string(body) {
		t.Errorf("got %q, want %q", got, body)
	}
}

func TestDownloadFileHTTPError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "not found", http.StatusNotFound)
	}))
	defer srv.Close()

	dir := t.TempDir()
	dest := filepath.Join(dir, "fail.bin")

	err := downloadFile(srv.URL+"/missing", dest)
	if err == nil {
		t.Fatal("expected error for 404")
	}
}
