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
	if err := os.WriteFile(invalidPath, []byte("not a zip"), 0644); err != nil {
		t.Fatal(err)
	}
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
	if err := os.MkdirAll(destDir, 0755); err != nil {
		t.Fatal(err)
	}

	// Build a zip with a file and a directory entry
	w, err := os.Create(zipPath)
	if err != nil {
		t.Fatalf("create zip: %v", err)
	}
	zw := zip.NewWriter(w)
	dh := &zip.FileHeader{Name: "subdir/"}
	dh.SetMode(0755 | os.ModeDir)
	var headerErr error
	if _, headerErr = zw.CreateHeader(dh); headerErr != nil {
		t.Fatalf("zip create dir header: %v", headerErr)
	}
	f, err := zw.Create("subdir/hello.txt")
	if err != nil {
		t.Fatalf("zip create entry: %v", err)
	}
	var writeErr error
	if _, writeErr = f.Write([]byte("hello world")); writeErr != nil {
		t.Fatalf("zip write: %v", writeErr)
	}
	if closeErr := zw.Close(); closeErr != nil {
		t.Fatalf("zip close: %v", closeErr)
	}
	if closeErr := w.Close(); closeErr != nil {
		t.Fatalf("file close: %v", closeErr)
	}

	if extractErr := extractZip(zipPath, destDir); extractErr != nil {
		t.Fatalf("extractZip: %v", extractErr)
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
	if err := os.MkdirAll(destDir, 0755); err != nil {
		t.Fatal(err)
	}

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
	var writeErr error
	if _, writeErr = f.Write([]byte("pwned")); writeErr != nil {
		t.Fatalf("zip write: %v", writeErr)
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
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		if _, err := w.Write(body); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
		}
	}))
	defer srv.Close()

	dir := t.TempDir()
	dest := filepath.Join(dir, "downloaded.bin")

	if err := downloadFile(srv.URL+"/test", dest); err != nil {
		t.Fatalf("downloadFile: %v", err)
	}

	got, err := os.ReadFile(dest)
	if err != nil {
		t.Fatalf("read downloaded file: %v", err)
	}
	if string(got) != string(body) {
		t.Errorf("got %q, want %q", got, body)
	}
}

func TestDownloadFileHTTPError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
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
