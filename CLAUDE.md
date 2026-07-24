# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

A Docker image for [LanguageTool](https://www.languagetool.org/) built on Alpine Linux with a custom minimal JRE, fasttext support, and automatic ngram model downloads. Published to Docker Hub as `meyay/languagetool`.

## Build commands

```bash
# Build the standard image (uses Alpine fasttext package)
docker build -t meyay/languagetool:latest .

# Build with compiled-from-source fasttext (for CPU compatibility issues)
sudo docker build -t meyay/languagetool:latest -f Dockerfile.fasttext .
sudo make docker_build   # same as above via Makefile

# Start the container locally
docker compose up -d

# Test the API after startup
curl --data "language=en-US&text=a simple test" http://127.0.0.1:8081/v2/check
```

## Architecture overview

### Multi-stage Dockerfile build

Both `Dockerfile` and `Dockerfile.fasttext` use the same multi-stage pattern:

1. **`base`** — pinned Alpine base image
2. **`java_base`** — base + locale/timezone packages
3. **`prepare`** — downloads Eclipse Temurin JDK + Apache Maven, clones LanguageTool from GitHub at the tag matching `LT_VERSION`, patches `pom.xml` for CVE fixes (logback, Jackson), builds with Maven, then uses `jlink` to produce a minimal custom JRE (`/opt/java/customjre`) with only the modules LanguageTool actually needs
4. **`fasttext`** (Dockerfile.fasttext only) — compiles fasttext from source with gcc13 patch + UPX compression
5. **`go_build`** — compiles the `entrypoint` Go binary (see below); `ARG GO_VERSION` must be declared in global scope (before the first `FROM`) so it can be referenced in the `FROM golang:${GO_VERSION}` line
6. **final** — copies `/languagetool` and `/opt/java/customjre` from `prepare`, installs runtime Alpine packages, sets up `languagetool` user (UID/GID 783)

### Dependency version management

Every pinned version in the Dockerfiles has a `# renovate:` comment above it. Renovate bot uses regular expression matching to track and auto-update these versions. When bumping any package or tool version, always update the corresponding `ARG` line and its renovate comment.

Direct CVE fixes are applied two ways:

- `pom.xml` patches via `xmlstarlet` (logback, Jackson) during the Maven build
- Direct JAR replacements via `wget` into `/languagetool/libs/` after extraction (netty, opennlp)

### Go entrypoint binary (`entrypoint/`)

The container entry point is a statically-linked Go binary (`CGO_ENABLED=0 GOOS=linux`, cross-compiled per target architecture — `amd64` and `arm64`) that replaces the former `entrypoint.sh`. It requires no shell, `su-exec`, `shadow`, or `xmlstarlet` in the runtime image. See `entrypoint/README.md` for the full startup sequence and environment variable reference.

Key implementation rules:

- **No hardcoded UID/GID numbers.** Effective UID/GID is derived once at startup: `MAP_UID`/`MAP_GID` env vars when root, `os.Getuid()`/`os.Getgid()` when unprivileged. Every downstream operation (ownership fix, download subprocess, privilege drop) uses this single computed value.
- **Download URLs/filenames live in `entrypoint/internal/download/downloads.yaml`** (embedded via `//go:embed`). Edit the YAML to update URLs; no Go recompile is needed.
- **Read-only filesystem detection** uses `syscall.Statfs("/", &stat)` checking `stat.Flags & 0x1` (ST_RDONLY). Do not parse `/proc/mounts`.
- **Privilege drop** uses `runtime.LockOSThread()` + `syscall.Setgid` + `syscall.Setuid` + `syscall.Exec`. Do not use `su-exec` or similar wrappers.
- **Download isolation**: when root, downloads are run by re-invoking the binary via `--_internal-run` with `exec.Cmd.SysProcAttr.Credential{Uid, Gid}` so downloaded files are owned by the target user.
- **`go mod tidy` runs inside the Docker `go_build` stage** — there is no local Go install requirement. The `go.sum` file is committed and kept up to date.
- **`go.sum` must be committed.** Run `go mod tidy` in `entrypoint/` after any dependency change.

### Image versioning

Tags follow the pattern `{LT_VERSION}-{sequential_number}` (e.g., `6.8-0`). The CI pipeline auto-increments the number by querying existing GitHub tags. `IMAGE_VERSION` and `IMAGE_CREATED` are build args set at build time.

### CI/CD pipeline (`.github/workflows/pipeline.yaml`)

1. **super-linter** — runs on PRs and feature branches only
2. **build-test-image** — builds and pushes to GHCR with the run ID as tag
3. **integration-test-image** — runs 6 scenarios × 2 platforms (ubuntu-latest, ubuntu-24.04-arm) from `.github/tests/` (privileged/unprivileged × rw/ro/no-volumes)
4. **scan-image** — Grype CVE scan (non-blocking on PRs/branches)
5. **cve-check-image-and-report** — blocking CVE scan, runs only on tags
6. **retag-and-push-final-image** — retags GHCR image and pushes to Docker Hub with versioned + `latest` tags; runs only on tags
7. **create-release-tag** — creates and pushes the next `{LT_VERSION}-{sequential_number}` git tag; only runs on a manual `workflow_dispatch` run on `main`. Pushing that tag re-triggers the pipeline, which then runs the CVE check, retag/push, and release steps above.
8. **create-github-release** — creates the GitHub release (with auto-generated notes) for the pushed tag; runs only on tags

**Branch naming:** the pipeline triggers on `feature/*` branches (not `feat/*`). Always use `feature/` as the branch prefix for development branches.

### Integration test compose files

Files in `.github/tests/` each define a specific runtime scenario. They all require the `IMAGE` environment variable to be set. The `privileged-*.yml` variants run as root with Linux capabilities; `unprivileged-*.yml` variants use `user: "1001:1001"`.

## Key constraints

- LanguageTool is built from GitHub tags (not release zips, which were discontinued after v6.6)
- The `patches/` directory contains version-specific patches: `gcc13.patch` (fasttext), `no-march-native.patch` (fasttext), `lt6_7_memory_leak_fix.patch` (applied conditionally in the Dockerfile only when `LT_VERSION == 6.7`)
- `/tmp` must be mounted as `tmpfs` with `exec` permissions — JNA extracts native libs there
- Default listen port is `8081` (changed from `8010` in version 6.6-0)

## Go development guidelines

When working on any `.go` file in this repository:

- **Use LSP instead of grep** for all code navigation and symbol lookup (finding definitions, references, implementations). Prefer `mcp__ide__getDiagnostics` and LSP-based tools over `grep`/`ripgrep` for Go source.
- **Follow Effective Go** conventions: <https://go.dev/doc/effective_go> — idiomatic naming, error handling, interfaces, and concurrency patterns.
- **Lint after every edit.** After modifying any Go file, run `golangci-lint run ./...` from `entrypoint/` before considering the task done. Fix all reported issues.
- **Format on save.** Run `gofmt -w` (or `goimports -w`) on every modified `.go` file.

## Formatting

Prettier is the authoritative formatter for YAML, Markdown, and JSON files in this repository (enforced by `YAML_PRETTIER`, `MARKDOWN_PRETTIER`, and `JSON_PRETTIER` in super-linter). Always run it before committing to avoid CI failures.

After modifying any `.yaml` file under `.github/workflows/`:

```bash
prettier --write ".github/workflows/*.yaml"
```

After modifying any `.md` file:

```bash
prettier --write "*.md"
```

After modifying any `.json` file:

```bash
prettier --write "*.json"
```

## Changelog

`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. Each release is a `## [tag] - date` section with `### Added`, `### Changed`, `### Fixed`, and `### Security` subsections (omit any that have no entries).

`CHANGELOG.md` is updated manually. When editing, follow the same structure.

`.markdownlint.json` sets `MD024: siblings_only: true` to allow the repeated category headings across version sections — do not remove this rule.

## Git conventions

- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/): `type(scope): description` (e.g. `feat(download): …`, `fix(entrypoint): …`, `chore(deps): …`, `refactor(mount): …`, `docs(entrypoint): …`).
- Feature branches must be named `feature/<name>` — the CI pipeline only triggers on `feature/*`, not `feat/*`.
