// Package download handles HTTPS downloads and zip extraction for ngram
// language models and the fasttext language-identification model.
package download

import (
	"archive/zip"
	_ "embed"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"syscall"

	"gopkg.in/yaml.v3"

	ilog "github.com/meyayl/docker-languagetool/internal/log"
)

//go:embed downloads.yaml
var downloadsConfigData []byte

type downloadsConfig struct {
	Ngrams struct {
		Languages map[string]string `yaml:"languages"`
	} `yaml:"ngrams"`
	Fasttext struct {
		ModelURL string `yaml:"model_url"`
	} `yaml:"fasttext"`
}

var cfg = mustParseConfig()

func mustParseConfig() downloadsConfig {
	var c downloadsConfig
	if err := yaml.Unmarshal(downloadsConfigData, &c); err != nil {
		panic(fmt.Sprintf("parse downloads.yaml: %v", err))
	}
	return c
}

// HandleNgramLanguageModels handles downloading and extracting ngram models.
// It should be called with the process running as the intended owner of
// languageModelDir (via SysProcAttr.Credential when root).
func HandleNgramLanguageModels(languageModelDir, downloadLangs string) error {
	if downloadLangs == "" || downloadLangs == "none" {
		ilog.Warn("\"download_ngrams_for_langs\" not provided, no ngrams will be downloaded.")
		return nil
	}
	if languageModelDir == "" {
		ilog.Error("No base path for ngram language models provided. Language Tool will not download ngram models. It will only use existing ngram models.")
		return nil
	}

	if err := validateDir(languageModelDir); err != nil {
		ilog.Error("%v", err)
		return err
	}

	if st, err := os.Stat(languageModelDir); err == nil {
		if stat, ok := st.Sys().(*syscall.Stat_t); ok {
			ilog.Info("Directory %s is owned by %d:%d", languageModelDir, stat.Uid, stat.Gid)
		}
	}

	for _, lang := range strings.Split(downloadLangs, ",") {
		lang = strings.TrimSpace(lang)
		if lang == "none" {
			continue
		}
		if _, ok := cfg.Ngrams.Languages[lang]; !ok {
			ilog.Error("Unknown ngrams language. Supported languages are \"en\", \"de\", \"es\", \"fr\" and \"nl\".")
			return fmt.Errorf("unknown ngrams language: %q", lang)
		}
		if err := downloadAndExtractNgramModel(languageModelDir, lang); err != nil {
			return err
		}
	}
	return nil
}

// DownloadFasttextModel downloads the fasttext model if absent.
// It should be called with the process running as the intended owner.
func DownloadFasttextModel(fasttextModelPath string, disableFasttext bool) error { //nolint:revive
	if fasttextModelPath == "" || disableFasttext {
		ilog.Info("\"langtool_fasttextModel\" not specified or \"DISABLE_FASTTEXT\" is set to \"true\". Skipping download of fasttext model.")
		return nil
	}

	parentDir := filepath.Dir(fasttextModelPath)
	if err := validateDir(parentDir); err != nil {
		ilog.Error("%v", err)
		return err
	}

	if st, err := os.Stat(parentDir); err == nil {
		if stat, ok := st.Sys().(*syscall.Stat_t); ok {
			ilog.Info("Directory %s is owned by %d:%d.", parentDir, stat.Uid, stat.Gid)
		}
	}

	if _, err := os.Stat(fasttextModelPath); err == nil {
		ilog.Info("Skipping download of fasttext model: already exists.")
		return nil
	}

	ilog.Info("Downloading fasttext model.")
	return downloadFile(cfg.Fasttext.ModelURL, fasttextModelPath)
}

func downloadAndExtractNgramModel(modelDir, lang string) error {
	langDir := filepath.Join(modelDir, lang)
	if _, err := os.Stat(langDir); err == nil {
		ilog.Info("Skipping download of ngram model for language %s: already exists.", lang)
		return nil
	}

	zipPath := filepath.Join(modelDir, "ngrams-"+lang+".zip")
	if _, err := os.Stat(zipPath); err != nil || !isValidZip(zipPath) {
		ilog.Info("Downloading %q ngrams.", lang)
		if err := downloadFile(cfg.Ngrams.Languages[lang], zipPath); err != nil {
			return fmt.Errorf("download ngrams %s: %w", lang, err)
		}
	}

	ilog.Info("Extracting %q ngram language model.", lang)
	if err := extractZip(zipPath, modelDir); err != nil {
		os.Remove(zipPath)
		return fmt.Errorf("extract ngrams %s: %w", lang, err)
	}
	os.Remove(zipPath)
	return nil
}

func validateDir(dir string) error {
	info, err := os.Stat(dir)
	if err != nil {
		return fmt.Errorf("directory %q not accessible: %w", dir, err)
	}

	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return fmt.Errorf("unexpected stat type for %q", dir)
	}

	uid := uint32(os.Getuid()) //nolint:gosec
	gid := uint32(os.Getgid()) //nolint:gosec

	mode := uint32(info.Mode())
	var perm uint32
	switch {
	case uid == 0:
		perm = 7
	case stat.Uid == uid:
		perm = (mode >> 6) & 7
	case stat.Gid == gid:
		perm = (mode >> 3) & 7
	default:
		perm = mode & 7
	}

	canExec := perm&1 != 0
	canWrite := perm&2 != 0

	var errs []error
	if !canExec && !canWrite {
		errs = append(errs, fmt.Errorf("directory %q does not allow the user or group to enter it or write into it", dir))
	}
	if stat.Uid != uid && stat.Gid != gid {
		errs = append(errs, fmt.Errorf("directory %q is owned by %d:%d, but should be owned by uid %d and/or gid %d",
			dir, stat.Uid, stat.Gid, uid, gid))
	}

	return errors.Join(errs...)
}

func isValidZip(path string) bool {
	r, err := zip.OpenReader(path)
	if err != nil {
		return false
	}
	r.Close()
	return true
}

func downloadFile(url, destPath string) error {
	resp, err := http.Get(url) //nolint:gosec // URL is controlled internally
	if err != nil {
		os.Remove(destPath)
		return fmt.Errorf("GET %s: %w", url, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		os.Remove(destPath)
		return fmt.Errorf("GET %s: status %s", url, resp.Status)
	}

	f, err := os.Create(destPath)
	if err != nil {
		return fmt.Errorf("create %s: %w", destPath, err)
	}
	defer f.Close()

	pw := &progressWriter{total: resp.ContentLength}
	w := io.MultiWriter(f, pw)
	if _, err := io.Copy(w, resp.Body); err != nil {
		f.Close()
		os.Remove(destPath)
		return fmt.Errorf("download %s: %w", url, err)
	}
	return nil
}

type progressWriter struct {
	total     int64
	written   int64
	lastPrint int64
}

func (pw *progressWriter) Write(p []byte) (int, error) {
	n := len(p)
	pw.written += int64(n)
	const printEvery = 10 * 1024 * 1024 // 10 MB
	if pw.written-pw.lastPrint >= printEvery {
		if pw.total > 0 {
			pct := pw.written * 100 / pw.total
			ilog.Line("  Downloaded %d MB (%d%%)", pw.written/(1024*1024), pct)
		} else {
			ilog.Line("  Downloaded %d MB", pw.written/(1024*1024))
		}
		pw.lastPrint = pw.written
	}
	return n, nil
}

func extractZip(zipPath, destDir string) error {
	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return fmt.Errorf("open zip %s: %w", zipPath, err)
	}
	defer r.Close()

	destDir = filepath.Clean(destDir)

	for _, f := range r.File {
		target := filepath.Join(destDir, filepath.FromSlash(f.Name))

		// guard against zip-slip path traversal
		if !strings.HasPrefix(filepath.Clean(target)+string(os.PathSeparator),
			destDir+string(os.PathSeparator)) {
			return fmt.Errorf("illegal path in zip: %q", f.Name)
		}

		ilog.Line("  Extracting: %s", f.Name)

		if f.FileInfo().IsDir() {
			if err := os.MkdirAll(target, f.Mode()); err != nil {
				return err
			}
			continue
		}

		if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
			return err
		}

		if err := extractZipFile(f, target); err != nil {
			return err
		}
	}
	return nil
}

func extractZipFile(f *zip.File, target string) error {
	rc, err := f.Open()
	if err != nil {
		return fmt.Errorf("open zip entry %s: %w", f.Name, err)
	}
	defer rc.Close()

	out, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, f.Mode())
	if err != nil {
		return fmt.Errorf("create %s: %w", target, err)
	}
	defer out.Close()

	_, err = io.Copy(out, rc) //nolint:gosec // ngram zip files are from trusted URLs embedded in downloads.yaml
	return err
}
