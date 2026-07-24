# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Image tags follow the pattern `{LanguageTool_version}-{sequential_number}` (e.g. `6.8-3`).

## [6.8-5] - 2026-07-24

### Changed

- Upgrade base image to Alpine 3.24.1
- Upgrade Go to 1.26.5
- Bump entrypoint dependency `github.com/beevik/etree` to 1.7.0

### Fixed

- Correct `tzdata` pin to 2026c-r0 (2026b-r0 was removed from the alpine_3_24 repository, breaking the build)

### Security

- Upgrade Go to 1.26.5, fixing CVE-2026-39822 (os.Root symlink escape outside the root on Unix) and CVE-2026-42505 (crypto/tls Encrypted Client Hello PSK identity leak in the outer ClientHello, CVSS 5.3 Medium)
- Patch Jackson to 2.18.9 via pom.xml, fixing GHSA-r7wm-3cxj-wff9 (jackson-core `StreamReadConstraints` bypass in the async parser via chunked digit accumulation, CVSS 5.3) and CVE-2026-54515 (jackson-databind case-insensitivity check reopened `@JsonIgnoreProperties`-excluded fields, CVSS 5.3 Medium)
- Patch logback to 1.5.35 via pom.xml, fixing CVE-2025-11226 (arbitrary code execution via conditional logback configuration processing, requires Janino + Spring on the classpath, CVSS v4 5.9 Medium) and CVE-2026-10532 (`HardenedObjectInputStream` Proxy-class deserialization whitelist bypass, CVSS v4 2.9 Low)

## [6.8-4] - 2026-06-11

### Changed

- Upgrade base image to Alpine 3.24.0
- Upgrade 7zip to 26.00
- Upgrade libstdc++ to 15.2.0-r5
- Upgrade fasttext to 0.9.2-r3

### Security

- Upgrade OpenSSL to 3.5.7s
- Patch lettuce 7.6.0.RELEASE via pom.xml
- Upgrade netty.io dependencies to 4.2.15.Final

## [6.8-3] - 2026-06-05

### Changed

- Upgrade Maven to 3.9.16
- Upgrade Go to 1.26.4
- Gate pom.xml CVE patches to LT_VERSION 6.8 only
- Remove direct netty JAR replacements from build

### Security

- Patch opennlp-tools 2.5.9, opentelemetry 1.62.0, lettuce 7.5.2 via pom.xml

## [6.8-2] - 2026-05-16

### Added

- Add `linux/arm64` build support
- Select Java JDK per target architecture
- Cross-compile Go entrypoint per target architecture

### Fixed

- Apply `no-march-native` patch to fasttext build for improved CPU compatibility

## [6.8-1] - 2026-05-15

### Changed

- Replace entrypoint shell script with a statically-linked Go binary to reduce the attack surface through package dependencies

## [6.8-0] - 2026-05-09

### Changed

- Upgrade to LanguageTool 6.8
- Upgrade Java to `jdk-21.0.11+10`
- Upgrade Maven to 3.9.15

### Security

- Upgrade `netty.io` dependencies to 4.2.13.Final

## [6.7-8] - 2026-04-18

### Changed

- Upgrade base image to Alpine 3.23.4

## [6.7-7] - 2026-02-28

### Security

- Fix GHSA-72hv-8253-57qq (High) by upgrading `com.fasterxml.jackson.core` from 2.18.0 to 2.18.6
- Upgrade `netty.io` dependencies from 4.1.127.Final to 4.1.131.Final

## [6.7-6] - 2026-02-18

### Security

- Replace `unzip` with `7zip` to remediate CVE-2008-0888

## [6.7-5] - 2026-02-15

### Fixed

- Correctly apply the LanguageTool 6.7 memory leak fix (supersedes 6.7-4)

## [6.7-4] - 2026-02-15 [YANKED]

### Fixed

- Patch LanguageTool 6.7 memory leak

### Changed

- Upgrade base image to Alpine 3.23.3
- Upgrade Java to `jdk-21.0.10+7`

### Security

- Fix CVE-2026-1225 (Low) by updating `ch.qos.logback` to 1.5.25

## [6.7-3] - 2025-11-25

### Changed

- Refactor CVE upgrade mechanism for Java dependencies: patch `pom.xml` for direct dependencies; replace transitive dependency JARs directly in `/languagetool/libs/` where the parent artifact cannot be upgraded via `pom.xml`

## [6.7-2] - 2025-10-25

### Fixed

- Fix download extraction failure caused by `unzip` in Alpine 3.22.2 (use edge package instead)

### Changed

- Upgrade Java to `21.0.9+10`

### Security

- Fix CVE-2025-11226 (Medium)

## [6.7-1] - 2025-10-10

### Changed

- Upgrade base image to Alpine 3.22.2

## [6.7-0] - 2025-10-09

### Changed

- Upgrade to LanguageTool 6.7

### Security

- Fix CVE-2025-49796 (Critical), CVE-2025-49794 (Critical), CVE-2025-49795 (High), CVE-2025-6021 (High), CVE-2025-6170 (Low)

## [6.6-7] - 2025-10-02

### Security

- Correctly fix CVE-2025-58057 (Medium), superseding the incomplete fix in 6.6-6

## [6.6-6] - 2025-10-02

### Fixed

- Fix use of local variables in entrypoint function `download_and_extract_ngram_language_model` (thanks @walery!)
- Switch image `HEALTHCHECK` to `/v2/healthcheck`

### Security

- Fix CVE-2025-9230 (High), CVE-2025-9231 (Medium), CVE-2025-9232 (Medium)
- Partial fix for CVE-2025-58057 (Medium) — fully remediated in 6.6-7

## [6.6-5] - 2025-08-29

### Changed

- Build LanguageTool from GitHub tags instead of release ZIP files

### Security

- Fix CVE-2008-0888 by using the Alpine edge release of the `unzip` package

## [6.6-4] - 2025-07-18

### Changed

- Upgrade base image to Alpine 3.22.1
- Upgrade Java to `21.0.8+9`

### Security

- Fix CVE-2025-48924 by replacing `org.apache.commons:commons-lang3:3.17.0` with `3.18.0`

## [6.6-3] - 2025-05-23

### Added

- Add `CONTAINER_MODE` environment variable for Kubernetes users who manage ngram model downloads in `initContainers`

## [6.6-2] - 2025-05-18

### Fixed

- Fix JNA error (`Error loading shared library /tmp/jna*.tmp: Operation not permitted`)

### Security

- Fix CVE-2025-32414 and CVE-2025-32415 in Alpine 3.21.3

## [6.6-1] - 2025-04-20

### Fixed

- Fix read-only filesystem compatibility for Synology DSM 6.2 with aufs

### Security

- Replace CVE-affected `logback-core` and `logback-classic` with version 1.5.18

## [6.6-0] - 2025-04-19

### Changed

- Upgrade to LanguageTool 6.6
- **Breaking:** Change default `LISTEN_PORT` from `8010` to `8081`
- Extend sanity checks and log output in entrypoint script
- Upgrade Java to `21.0.7+6`

## [6.5-2] - 2025-02-16

### Changed

- Upgrade base image to Alpine 3.21.3
- Upgrade Java to `21.0.6+7`

## [6.5-1] - 2024-10-30

### Changed

- Refactor entrypoint script
- Upgrade Java to `21.0.5+11`

## [6.5-0] - 2024-09-29

### Changed

- Upgrade to LanguageTool 6.5

## [6.4-4] - 2024-09-14

### Changed

- Upgrade base image to Alpine 3.20.3

## [6.4-3] - 2024-07-31

### Changed

- Upgrade base image to Alpine 3.20.2
- Upgrade Java to `21.0.4+7`

## [6.4-2] - 2024-07-05

### Changed

- Upgrade base image to Alpine 3.20.1
- Upgrade Java to `21.0.3+9`

## [6.4-1] - 2024-05-27

### Changed

- Upgrade base image to Alpine 3.20.0

## [6.4-0] - 2024-04-02

### Changed

- Upgrade to LanguageTool 6.4
- Require `755` (not `777`) permissions for ngrams and fasttext volume mounts

## [6.3a-5] - 2024-03-26

### Changed

- Upgrade Java to `21.0.2+13`
- Document `CAP_CHOWN` capability requirement in `README.md` and compose file

## [6.3a-4] - 2024-02-26

### Fixed

- Fix entrypoint bug that prevented new users from downloading ngram models

## [6.3a-3] - 2024-02-17

### Changed

- Upgrade base image to Alpine 3.19.1
- Replace compiled-from-source fasttext with the Alpine `fasttext` package

## [6.3a-2] - 2024-02-17

### Changed

- Create the `languagetool` user without a home directory
- Update `uid:gid` of the `languagetool` user and group at startup when they differ from the requested mapping

## [6.3a-1] - 2024-02-12

### Changed

- Upgrade base image to Alpine 3.18.6
- Upgrade Java to `17.0.10+7`

## [6.3a-0] - 2023-12-20

### Changed

- Upgrade to LanguageTool 6.3a

## [6.3-1] - 2023-12-03

### Changed

- Upgrade base image to Alpine 3.18.5
- Upgrade Java to `17.0.9+9`

## [6.3-0] - 2023-10-10

### Changed

- Upgrade to LanguageTool 6.3
- Upgrade base image to Alpine 3.18.4
- Upgrade Java to `17.0.8.1+1`

## [6.2-1] - 2023-08-10

### Changed

- Upgrade base image to Alpine 3.18.3
- Upgrade Java to `17.0.8+7`

## [6.2-0] - 2023-07-09

### Changed

- Upgrade to LanguageTool 6.2

## [6.1-4] - 2023-06-30

### Changed

- Upgrade base image to Alpine 3.18.2

## [6.1-3] - 2023-05-19

### Changed

- Upgrade base image to Alpine 3.18.0
- Upgrade Java to `17.0.7+7`

## [6.1-2] - 2023-04-01

### Changed

- Upgrade base image to Alpine 3.17.3

## [6.1-1] - 2023-03-28

### Added

- Add configurable log level via environment variable

## [6.1-0] - 2023-03-28

### Changed

- Upgrade to LanguageTool 6.1

## [6.0-5] - 2023-02-23

### Changed

- Upgrade base image to Alpine 3.17.2

## [6.0-4] - 2023-01-23

### Changed

- Upgrade Java to Eclipse Temurin `17.0.6+10`

## [6.0-3] - 2023-01-15

### Changed

- Upgrade base image to Alpine 3.17.1

## [6.0-2] - 2023-01-01

### Fixed

- Add Alpine package `gcompat` to satisfy `ld-linux-x86-64.so.2` dependency (resolves crash introduced in 6.0-1)

## [6.0-1] - 2022-12-29 [YANKED]

### Changed

- Upgrade to LanguageTool 6.0

> Removed due to a `ClassPath` exception at startup.

## [5.9-7] - 2022-12-07

### Fixed

- Fix health check command

## [5.9-6] - 2022-12-04

### Added

- Add `help` command to display available LanguageTool configuration keys for use with `languagetool_*` environment variables

## [5.9-5] - 2022-12-04

### Added

- Add `tini` as PID 1 to suppress spurious exit code 143
- Print Alpine and Eclipse Temurin version info at container startup

### Changed

- Switch to a stripped-down Eclipse Temurin 17 JRE
- Remove JVM argument `-XX:+UseStringDeduplication` except when using G1GC
- Replace `curl` with `wget`

## [5.9-4] - 2022-11-29

### Changed

- Upgrade base image to Alpine 3.17.0

## [5.9-3] - 2022-11-24

### Added

- Add support for configuring the JVM garbage collector
- Add support for passing custom `JAVA_OPTS`
- Add JVM argument `-XX:+UseStringDeduplication`

### Changed

- Rename `Java_Xm?` environment variables to `JAVA_XM?`

## [5.9-2] - 2022-11-12

### Changed

- Upgrade base image to Alpine 3.16.3

## [5.9-1] - 2022-09-28

### Changed

- Upgrade LanguageTool to 5.9

## [5.8-2] - 2022-09-10

### Added

- Add user mapping support (`MAP_UID`/`MAP_GID`)

## [5.8-1] - 2022-09-10

### Added

- Initial release with Alpine 3.16.2 and LanguageTool 5.8
