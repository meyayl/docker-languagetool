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
5. **final** — copies `/languagetool` and `/opt/java/customjre` from `prepare`, installs runtime Alpine packages, sets up `languagetool` user (UID/GID 783)

### Dependency version management

Every pinned version in the Dockerfiles has a `# renovate:` comment above it. Renovate bot uses regex matching to track and auto-update these versions. When bumping any package or tool version, always update the corresponding `ARG` line and its renovate comment.

Direct CVE fixes are applied two ways:
- `pom.xml` patches via `xmlstarlet` (logback, Jackson) during the Maven build
- Direct JAR replacements via `wget` into `/languagetool/libs/` after extraction (netty, opennlp)

### entrypoint.sh

The entrypoint handles everything at container start:

- **Root mode** (default): maps UID/GID via `usermod`/`groupmod` (or `nss_wrapper` on read-only filesystems), optionally fixes volume ownership via `chown`
- **Unprivileged mode**: skips user mapping, expects volumes pre-owned correctly
- Downloads ngram models (en/de/es/fr/nl) and fasttext model if not already present
- Generates `/tmp/config.properties` by iterating all `langtool_*` environment variables — any env var prefixed with `langtool_` is automatically written as a config key
- Sets log level by patching `/tmp/logback.xml` via `xmlstarlet`
- Launches LanguageTool via `su-exec` (root mode) or `exec` (unprivileged)

### Image versioning

Tags follow the pattern `{LT_VERSION}-{sequential_number}` (e.g., `6.8-0`). The CI pipeline auto-increments the number by querying existing GitHub tags. `IMAGE_VERSION` and `IMAGE_CREATED` are build args set at build time.

### CI/CD pipeline (`.github/workflows/pipeline.yaml`)

1. **super-linter** — runs on PRs and feature branches only
2. **build-test-image** — builds and pushes to GHCR with the run ID as tag
3. **integration-test-image** — runs 6 matrix scenarios from `.github/tests/` (privileged/unprivileged × rw/ro/no-volumes)
4. **scan-image** — Grype CVE scan (non-blocking on PRs/branches)
5. **cve-check-image-and-report** — blocking CVE scan, runs only on tags
6. **retag-and-push-final-image** — retags GHCR image and pushes to Docker Hub with versioned + `latest` tags; runs only on tags

### Integration test compose files

Files in `.github/tests/` each define a specific runtime scenario. They all require the `IMAGE` environment variable to be set. The `privileged-*.yml` variants run as root with Linux capabilities; `unprivileged-*.yml` variants use `user: "1001:1001"`.

## Key constraints

- LanguageTool is built from GitHub tags (not release zips, which were discontinued after v6.6)
- The `patches/` directory contains version-specific patches: `gcc13.patch` (fasttext), `no-march-native.patch` (fasttext), `lt6_7_memory_leak_fix.patch` (applied conditionally in the Dockerfile only when `LT_VERSION == 6.7`)
- `/tmp` must be mounted as `tmpfs` with `exec` permissions — JNA extracts native libs there
- Default listen port is `8081` (changed from `8010` in version 6.6-0)
