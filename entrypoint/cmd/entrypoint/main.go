package main

import (
	"bufio"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
	"syscall"

	"github.com/meyayl/docker-languagetool/internal/caps"
	"github.com/meyayl/docker-languagetool/internal/config"
	"github.com/meyayl/docker-languagetool/internal/download"
	ilog "github.com/meyayl/docker-languagetool/internal/log"
	"github.com/meyayl/docker-languagetool/internal/logback"
	"github.com/meyayl/docker-languagetool/internal/mount"
	"github.com/meyayl/docker-languagetool/internal/nss"
	"github.com/meyayl/docker-languagetool/internal/ownership"
	"github.com/meyayl/docker-languagetool/internal/system"
)

// Config holds all environment-driven configuration and derived runtime state.
type Config struct {
	MapUID    uint32
	MapGID    uint32
	MapUIDSet bool
	MapGIDSet bool

	DownloadNgramsForLangs string
	LangtoolLanguageModel  string
	LangtoolFasttextModel  string
	LangtoolFasttextBinary string
	DisableFasttext        bool

	DisableFileOwnerFix bool
	ContainerMode       string

	JavaOpts string
	JavaGC   string
	JavaXMS  string
	JavaXMX  string

	LogLevel      string
	LogbackConfig string
	ListenPort    string

	DebugEntrypoint bool
}

func main() {
	if len(os.Args) >= 2 && os.Args[1] == "healthcheck" {
		runHealthcheck()
	}

	// Internal sub-command: re-invoked as a subprocess with a different uid/gid
	// to run downloads as the mapped user.
	if len(os.Args) >= 3 && os.Args[1] == "--_internal-run" {
		cfg := parseConfig()
		switch os.Args[2] {
		case "download-ngrams":
			if err := download.HandleNgramLanguageModels(cfg.LangtoolLanguageModel, cfg.DownloadNgramsForLangs); err != nil {
				ilog.Error("%v", err)
				os.Exit(1)
			}
		case "download-fasttext":
			if err := download.DownloadFasttextModel(cfg.LangtoolFasttextModel, cfg.DisableFasttext); err != nil {
				ilog.Error("%v", err)
				os.Exit(1)
			}
		default:
			ilog.Error("unknown internal sub-command: %q", os.Args[2])
			os.Exit(1)
		}
		return
	}

	if err := run(); err != nil {
		ilog.Error("%v", err)
		os.Exit(1)
	}
}

func run() error {
	cfg := parseConfig()

	// help must be checked before anything else
	if len(os.Args) >= 2 && os.Args[1] == "help" {
		return runHelp()
	}

	isRoot := os.Getuid() == 0

	// effectiveUID/GID is the identity used for ownership fixes, download
	// subprocesses, and the final privilege drop before exec. When root, this
	// comes from MAP_UID/MAP_GID (env vars, defaulting to the languagetool
	// image defaults). When unprivileged, it is the actual OS process identity.
	var effectiveUID, effectiveGID uint32
	if isRoot {
		effectiveUID, effectiveGID = cfg.MapUID, cfg.MapGID
	} else {
		effectiveUID = uint32(os.Getuid())
		effectiveGID = uint32(os.Getgid())
	}

	useNSSWrapper := false

	if isRoot {
		ilog.Info("Container started as root user.")
		ilog.Info("Available capabilities:")
		if err := caps.PrintCapabilities(os.Stdout); err != nil {
			ilog.Warn("could not read capabilities: %v", err)
		}

		// Determine if we need nss_wrapper (read-only root filesystem + UID/GID mismatch)
		isRO, err := mount.IsROMount()
		if err != nil {
			ilog.Warn("could not detect root mount type: %v", err)
		}

		if isRO {
			ilog.Info("Container started with readonly filesystem.")
			ltUser, err := system.LookupUser("languagetool")
			if err == nil {
				if (cfg.MapUIDSet && effectiveUID != ltUser.UID) || (cfg.MapGIDSet && effectiveGID != ltUser.GID) {
					useNSSWrapper = true
				}
			}
			if useNSSWrapper {
				if err := nss.SetupNSSWrapper(effectiveUID, effectiveGID); err != nil {
					return fmt.Errorf("nss_wrapper setup: %w", err)
				}
				ilog.Info("using nss_wrapper to set uid for user \"languagetool\" to %d and gid for group \"languagetool\" to %d.", effectiveUID, effectiveGID)
			}
		}

		if !useNSSWrapper {
			if err := system.UpdateUserMapping(effectiveUID, cfg.MapUIDSet, effectiveGID, cfg.MapGIDSet); err != nil {
				return fmt.Errorf("user mapping: %w", err)
			}
		}

		ownerFix := true
		if cfg.DisableFileOwnerFix {
			ownerFix = false
			ilog.Info("Container started with DISABLE_FILE_OWNER_FIX=%v. This disables the ownership fix of directories.", cfg.DisableFileOwnerFix)
		}

		capChown, _ := caps.IsEnabled(caps.CapChown)
		capDAC, _ := caps.IsEnabled(caps.CapDACOverride)

		if ownerFix && capChown && capDAC {
			if err := ownership.FixOwnership(cfg.LangtoolLanguageModel, cfg.LangtoolFasttextModel,
				effectiveUID, effectiveGID); err != nil {
				ilog.Warn("ownership fix error: %v", err)
			}
		} else {
			ilog.Warn("Container started without sufficient capabilities to fix ownership of directories.")
			ilog.Line("  Make sure the volumes have have the correct permissions and are owned by %d:%d.", effectiveUID, effectiveGID)
		}
	} else {
		ilog.Info("Container started as unprivileged UID:GID %d:%d. Skipping User mapping.", effectiveUID, effectiveGID)
		ilog.Line("      Make sure the volumes have have the correct permissions and are owned by %d:%d.", effectiveUID, effectiveGID)
	}

	// Run downloads as the mapped user when running as root
	if isRoot {
		if err := runDownloadsAsUser(effectiveUID, effectiveGID, "download-ngrams"); err != nil {
			return fmt.Errorf("download ngrams: %w", err)
		}
		if err := runDownloadsAsUser(effectiveUID, effectiveGID, "download-fasttext"); err != nil {
			return fmt.Errorf("download fasttext: %w", err)
		}
	} else {
		if err := download.HandleNgramLanguageModels(cfg.LangtoolLanguageModel, cfg.DownloadNgramsForLangs); err != nil {
			return fmt.Errorf("download ngrams: %w", err)
		}
		if err := download.DownloadFasttextModel(cfg.LangtoolFasttextModel, cfg.DisableFasttext); err != nil {
			return fmt.Errorf("download fasttext: %w", err)
		}
	}

	if cfg.ContainerMode == "download-only" {
		ilog.Info("Variable \"CONTAINER_MODE\" set to \"download-only\". Stopping the container.")
		return nil
	}

	// Fasttext validation
	if !cfg.DisableFasttext {
		if cfg.LangtoolFasttextBinary == "" {
			ilog.Info("Variable \"langtool_fasttextBinary\" not set. Fasttext can not be used.")
			cfg.DisableFasttext = true
		} else if info, err := os.Stat(cfg.LangtoolFasttextBinary); os.IsNotExist(err) {
			ilog.Warn("Fasttext binary not found at \"%s\". Fasttext can not be used.", cfg.LangtoolFasttextBinary)
			cfg.DisableFasttext = true
		} else if err != nil {
			ilog.Warn("Fasttext binary stat \"%s\": %v. Fasttext can not be used.", cfg.LangtoolFasttextBinary, err)
			cfg.DisableFasttext = true
		} else if info.Mode()&0111 == 0 {
			ilog.Warn("Fasttext binary has no execution permission \"%s\". Fasttext can not be used.", cfg.LangtoolFasttextBinary)
			cfg.DisableFasttext = true
		}

		if cfg.LangtoolFasttextModel == "" {
			ilog.Info("Variable \"langtool_fasttextModel\" not set. Fasttext can not be used.")
			cfg.DisableFasttext = true
		} else if _, err := os.Stat(cfg.LangtoolFasttextModel); os.IsNotExist(err) {
			ilog.Warn("Fasttext model not found at \"%s\". Fasttext can not be used.", cfg.LangtoolFasttextModel)
			cfg.DisableFasttext = true
		}
	}

	if cfg.DisableFasttext {
		ilog.Warn("Fasttext support is disabled.")
		os.Unsetenv("langtool_fasttextModel")
		os.Unsetenv("langtool_fasttextBinary")
		cfg.LangtoolFasttextModel = ""
		cfg.LangtoolFasttextBinary = ""
	}

	// Generate /tmp/config.properties from langtool_* env vars.
	// Must happen after fasttext vars are potentially unset.
	const configFile = "/tmp/config.properties"
	written, err := config.WriteConfigProperties(configFile)
	if err != nil {
		return fmt.Errorf("write config: %w", err)
	}

	if err := printVersionInfo(); err != nil {
		ilog.Warn("version info: %v", err)
	}

	if written {
		ilog.Info("Using following LanguageTool configuration:")
		if err := config.PrintConfig(configFile); err != nil {
			ilog.Warn("print config: %v", err)
		}
	}

	javaOpts, err := buildJavaOpts(cfg)
	if err != nil {
		return err
	}

	const logbackDst = "/tmp/logback.xml"
	if err := logback.PatchLogLevel(cfg.LogbackConfig, logbackDst, cfg.LogLevel); err != nil {
		return fmt.Errorf("patch logback: %w", err)
	}

	// Handle custom command (any args other than "help")
	if len(os.Args) > 1 {
		customArgs := os.Args[1:]
		customPath, err := exec.LookPath(customArgs[0])
		if err != nil {
			return fmt.Errorf("look up %q: %w", customArgs[0], err)
		}
		if isRoot {
			return execWithPrivilegeDrop(effectiveUID, effectiveGID, customPath, customArgs, os.Environ())
		}
		return syscall.Exec(customPath, customArgs, os.Environ())
	}

	// Start LanguageTool server
	ilog.Info("Starting Language Tool Standalone Server (or custom command)")
	ilog.Line("--------------------------------------------------------------------")

	javaPath, err := exec.LookPath("java")
	if err != nil {
		return fmt.Errorf("java not found in PATH: %w", err)
	}

	listenPort := cfg.ListenPort
	if listenPort == "" {
		listenPort = "8081"
	}

	javaArgs := []string{"java"}
	javaArgs = append(javaArgs, strings.Fields(javaOpts)...)
	javaArgs = append(javaArgs,
		"-Djna.tmpdir=/tmp",
		"-Dlogback.configurationFile=/tmp/logback.xml",
		"-cp", "languagetool-server.jar",
		"org.languagetool.server.HTTPServer",
		"--port", listenPort,
		"--public",
		"--allow-origin", "*",
		"--config", "/tmp/config.properties",
	)

	if isRoot {
		return execWithPrivilegeDrop(effectiveUID, effectiveGID, javaPath, javaArgs, os.Environ())
	}
	return syscall.Exec(javaPath, javaArgs, os.Environ())
}

// runHelp runs java --help and prints the relevant section (from --config FILE
// up to but not including --port), matching the shell script filter.
func runHelp() error {
	cmd := exec.Command("java", "-cp", "languagetool-server.jar",
		"org.languagetool.server.HTTPServer", "--help")
	out, _ := cmd.CombinedOutput() // java --help exits non-zero; that's expected

	printing := false
	scanner := bufio.NewScanner(strings.NewReader(string(out)))
	for scanner.Scan() {
		line := scanner.Text()
		if strings.Contains(line, "--config FILE") {
			printing = true
		}
		if strings.Contains(line, "--port") {
			printing = false
		}
		if printing {
			fmt.Println(line)
		}
	}
	return nil
}

// runHealthcheck performs an HTTP GET to /v2/healthcheck on LISTEN_PORT and
// exits 0 on a 2xx response, 1 otherwise. Designed for use as a Docker HEALTHCHECK.
func runHealthcheck() {
	port := os.Getenv("LISTEN_PORT")
	if port == "" {
		port = "8081"
	}
	resp, err := http.Get("http://localhost:" + port + "/v2/healthcheck") //nolint:noctx
	if err != nil {
		os.Exit(1)
	}
	resp.Body.Close()
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		os.Exit(0)
	}
	os.Exit(1)
}

// runDownloadsAsUser re-invokes the binary as a subprocess with the given
// uid/gid so that downloaded files are owned by the mapped user.
func runDownloadsAsUser(uid, gid uint32, subCmd string) error {
	self, err := os.Executable()
	if err != nil {
		return fmt.Errorf("resolve self: %w", err)
	}
	cmd := exec.Command(self, "--_internal-run", subCmd)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = os.Environ()
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Credential: &syscall.Credential{Uid: uid, Gid: gid},
	}
	return cmd.Run()
}

// execWithPrivilegeDrop drops to uid:gid then replaces the current process
// via syscall.Exec. LockOSThread ensures the setuid/setgid affect the
// correct OS thread before exec.
func execWithPrivilegeDrop(uid, gid uint32, path string, args []string, env []string) error {
	runtime.LockOSThread()
	if err := syscall.Setgid(int(gid)); err != nil {
		return fmt.Errorf("setgid %d: %w", gid, err)
	}
	if err := syscall.Setuid(int(uid)); err != nil {
		return fmt.Errorf("setuid %d: %w", uid, err)
	}
	return syscall.Exec(path, args, env)
}

// buildJavaOpts constructs the JAVA_OPTS string from config.
func buildJavaOpts(cfg Config) (string, error) {
	if cfg.JavaOpts != "" {
		ilog.Line("JAVA_OPTS environment variables detected.")
		ilog.Info("Using JAVA_OPTS=%s", cfg.JavaOpts)
		return cfg.JavaOpts, nil
	}

	gc := cfg.JavaGC
	if gc == "" {
		gc = "ShenandoahGC"
	}

	validGCs := []string{"ShenandoahGC", "SerialGC", "ParallelGC", "ParNewGC", "G1GC", "ZGC"}
	gcOpt := ""
	for _, v := range validGCs {
		if gc == v {
			gcOpt = "-XX:+Use" + v
			if v == "G1GC" {
				gcOpt += " -XX:+UseStringDeduplication"
			}
			break
		}
	}

	xms := cfg.JavaXMS
	if xms == "" {
		xms = "256m"
	}
	xmx := cfg.JavaXMX
	if xmx == "" {
		xmx = "1536m"
	}

	opts := fmt.Sprintf("-Xms%s -Xmx%s %s", xms, xmx, gcOpt)
	opts = strings.TrimSpace(opts)
	ilog.Info("Using JAVA_OPTS=%s", opts)
	return opts, nil
}

// printVersionInfo prints Alpine and Java version information.
func printVersionInfo() error {
	ilog.Info("Version Information:")

	data, err := os.ReadFile("/etc/os-release")
	if err != nil {
		return fmt.Errorf("read /etc/os-release: %w", err)
	}
	alpineVersion := ""
	for _, line := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(line, "VERSION_ID=") {
			alpineVersion = strings.Trim(strings.TrimPrefix(line, "VERSION_ID="), "\"")
			break
		}
	}
	fmt.Printf("  Alpine Linux v%s\n", alpineVersion)

	javaCmd := exec.Command("java", "--version")
	javaOut, _ := javaCmd.CombinedOutput()
	for _, line := range strings.Split(strings.TrimRight(string(javaOut), "\n"), "\n") {
		fmt.Printf("  %s\n", line)
	}
	return nil
}

// parseConfig reads all configuration from environment variables.
func parseConfig() Config {
	cfg := Config{
		DownloadNgramsForLangs: os.Getenv("download_ngrams_for_langs"),
		LangtoolLanguageModel:  os.Getenv("langtool_languageModel"),
		LangtoolFasttextModel:  os.Getenv("langtool_fasttextModel"),
		LangtoolFasttextBinary: os.Getenv("langtool_fasttextBinary"),
		DisableFasttext:        os.Getenv("DISABLE_FASTTEXT") == "true",
		DisableFileOwnerFix:    os.Getenv("DISABLE_FILE_OWNER_FIX") == "true",
		ContainerMode:          os.Getenv("CONTAINER_MODE"),
		JavaOpts:               os.Getenv("JAVA_OPTS"),
		JavaGC:                 os.Getenv("JAVA_GC"),
		JavaXMS:                os.Getenv("JAVA_XMS"),
		JavaXMX:                os.Getenv("JAVA_XMX"),
		LogLevel:               os.Getenv("LOG_LEVEL"),
		LogbackConfig:          os.Getenv("LOGBACK_CONFIG"),
		ListenPort:             os.Getenv("LISTEN_PORT"),
		DebugEntrypoint:        os.Getenv("DEBUG_ENTRYPOINT") == "true",
	}

	if uid, set, err := parseUint32Env("MAP_UID"); err == nil {
		cfg.MapUID = uid
		cfg.MapUIDSet = set
	}
	if gid, set, err := parseUint32Env("MAP_GID"); err == nil {
		cfg.MapGID = gid
		cfg.MapGIDSet = set
	}

	if cfg.LogLevel == "" {
		cfg.LogLevel = "INFO"
	}

	return cfg
}

func parseUint32Env(key string) (uint32, bool, error) {
	s := os.Getenv(key)
	if s == "" {
		return 0, false, nil
	}
	v, err := strconv.ParseUint(s, 10, 32)
	if err != nil {
		return 0, true, fmt.Errorf("invalid %s=%q: %w", key, s, err)
	}
	return uint32(v), true, nil
}
