# entrypoint

Static Go binary that replaces the original `entrypoint.sh` shell script as the container entry point for the `meyay/languagetool` Docker image. It requires no shell, no `su-exec`, no `shadow`, and no `xmlstarlet` in the runtime image.

## What it does

On every container start the binary runs the following sequence:

1. **Privilege detection** – checks `os.Getuid()` to decide whether it is running as root or as an unprivileged user.

2. **User/group mapping** (root only)
   - Reads Linux capabilities from `/proc/self/status` (`CAP_CHOWN`, `CAP_DAC_OVERRIDE`, `CAP_SETUID`, `CAP_SETGID`).
   - Detects whether the root filesystem is read-only via `syscall.Statfs`.
     - **Read-write filesystem**: rewrites `/etc/passwd` and `/etc/group` atomically to remap the `languagetool` user/group to the configured `MAP_UID`/`MAP_GID`.
     - **Read-only filesystem**: writes temporary `nss_wrapper` passwd/group files and sets `LD_PRELOAD`, `NSS_WRAPPER_PASSWD`, `NSS_WRAPPER_GROUP` instead.

3. **Ownership fix** (root + `CAP_CHOWN` + `CAP_DAC_OVERRIDE` only) – walks the ngrams directory and the fasttext model directory with `filepath.WalkDir` and `os.Lchown` to ensure volumes are owned by the effective UID/GID before the privilege drop.

4. **Downloads** – re-invokes itself via `--_internal-run` with `SysProcAttr.Credential` set to the effective UID/GID so downloaded files are owned by the target user from the start.
   - Ngram language models (ZIP archives fetched over HTTPS, extracted in-place).
   - fasttext language identification model (single binary file).
   - Download URLs and filenames are read from the embedded `downloads.yaml`; no recompile is needed to update them.

5. **LanguageTool configuration** – collects all environment variables whose names start with `langtool_`, strips the prefix, and writes them as `KEY=VALUE` pairs to `/tmp/config.properties`.

6. **Logback patching** – copies the logback config from `LOGBACK_CONFIG` to `/tmp/logback.xml` and sets the `org.languagetool` logger level to `LOG_LEVEL` using `beevik/etree`.

7. **Privilege drop + exec** (root only) – calls `runtime.LockOSThread()`, `syscall.Setgid`, `syscall.Setuid`, then `syscall.Exec` to replace the process with the Java server running as the effective UID/GID.

## Environment variables

| Variable                    | Default                 | Description                                                                                   |
| --------------------------- | ----------------------- | --------------------------------------------------------------------------------------------- |
| `MAP_UID`                   | `783`                   | UID to run the `languagetool` user as                                                         |
| `MAP_GID`                   | `783`                   | GID to run the `languagetool` group as                                                        |
| `DISABLE_FILE_OWNER_FIX`    | `false`                 | Skip the volume ownership walk                                                                |
| `DISABLE_FASTTEXT`          | `false`                 | Skip fasttext model download and disable fasttext                                             |
| `download_ngrams_for_langs` | `none`                  | Comma-separated list of languages to download ngram models for (`en`, `de`, `es`, `fr`, `nl`) |
| `langtool_languageModel`    | `/ngrams`               | Path to the ngram models directory                                                            |
| `langtool_fasttextModel`    | `/fasttext/lid.176.bin` | Path to the fasttext model file                                                               |
| `langtool_fasttextBinary`   | `/usr/bin/fasttext`     | Path to the fasttext binary                                                                   |
| `langtool_*`                | —                       | Any variable prefixed `langtool_` is passed to LanguageTool as a config property              |
| `LOG_LEVEL`                 | `INFO`                  | Logback log level for `org.languagetool`                                                      |
| `LOGBACK_CONFIG`            | `./logback.xml`         | Source logback config file                                                                    |
| `LISTEN_PORT`               | `8081`                  | HTTP port LanguageTool listens on                                                             |
| `CONTAINER_MODE`            | `default`               | Set to `download-only` to exit after downloads complete                                       |
| `JAVA_OPTS`                 | —                       | Passed verbatim to `java`; overrides `JAVA_GC`/`JAVA_XMS`/`JAVA_XMX`                          |
| `JAVA_GC`                   | `ShenandoahGC`          | GC algorithm (`ShenandoahGC`, `SerialGC`, `ParallelGC`, `ParNewGC`, `G1GC`, `ZGC`)            |
| `JAVA_XMS`                  | `256m`                  | JVM initial heap size                                                                         |
| `JAVA_XMX`                  | `1536m`                 | JVM maximum heap size                                                                         |

## Special invocation

```text
/entrypoint help
```

Runs `java -cp languagetool-server.jar org.languagetool.server.HTTPServer --help` and prints the LanguageTool-specific flags (from `--config FILE` up to but not including `--port`).

## Package layout

```text
cmd/entrypoint/main.go   – startup orchestration, privilege drop, Java exec
internal/caps/           – read Linux capabilities from /proc/self/status
internal/config/         – write /tmp/config.properties from langtool_* env vars
internal/download/       – HTTPS download, zip extraction, ngram + fasttext handling
  downloads.yaml         – embedded URL/filename config (edit to update without recompile)
internal/log/            – coloured INFO/WARN/ERROR helpers
internal/logback/        – patch logback.xml log level via beevik/etree
internal/mount/          – detect read-only root filesystem via syscall.Statfs
internal/nss/            – write nss_wrapper temp files and set env vars
internal/ownership/      – recursive chown via filepath.WalkDir + os.Lchown
internal/system/         – atomic /etc/passwd and /etc/group modification
```

## Building

The binary is built inside the Docker `go_build` stage — no local Go installation is required:

```dockerfile
FROM golang:1.24-alpine3.23 AS go_build
WORKDIR /src
COPY entrypoint/go.mod ./
COPY entrypoint/cmd/ cmd/
COPY entrypoint/internal/ internal/
RUN go mod tidy && \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o /entrypoint ./cmd/entrypoint
```

To build and test locally (requires Go 1.24+):

```bash
cd entrypoint
go test ./...
go build -o /tmp/entrypoint ./cmd/entrypoint
```
