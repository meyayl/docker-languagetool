ARG IMAGE_VERSION="6.8-5"
ARG IMAGE_CREATED="2026-07-18"
# renovate: datasource=github-tags depName=languagetool-org/languagetool versioning=loose
ARG LT_VERSION="6.8"
# renovate: datasource=github-releases depName=adoptium/temurin21-binaries versioning=regex:^jdk-(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)\+(?<build>\d+)$
ARG JAVA_VERSION="jdk-21.0.11+10"
# renovate: datasource=github-releases depName=apache/maven versioning=semver extractVersion=^maven-(?<version>.*)$
ARG MAVEN_VERSION="3.9.16"
# renovate: datasource=docker depName=golang versioning=docker
ARG GO_VERSION="1.26.4-alpine3.24"
FROM alpine:3.24.0 AS base

FROM base AS java_base

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# renovate: datasource=repology depName=alpine_3_24/libretls versioning=loose
ARG LIBRETLS_VERSION="3.8.1-r0"
# renovate: datasource=repology depName=alpine_3_24/musl-locales versioning=loose
ARG MUSL_LOCALES_VERSION="0.1.0-r1"
# renovate: datasource=repology depName=alpine_3_24/musl-locales-lang versioning=loose
ARG MUSL_LOCALES_LANG_VERSION="0.1.0-r1"
# renovate: datasource=repology depName=alpine_3_24/tzdata versioning=loose
ARG TZDATA_VERSION="2026c-r0"
# renovate: datasource=repology depName=alpine_3_24/zlib versioning=loose
ARG ZLIB_VERSION="1.3.2-r0"
# renovate: datasource=repology depName=alpine_3_24/openssl versioning=loose
ARG OPENSSL_VERSION="3.5.7s-r0"

RUN set -eux; \
    apk add --upgrade --no-cache \
     libretls="${LIBRETLS_VERSION}" \
     musl-locales="${MUSL_LOCALES_VERSION}" \
     musl-locales-lang="${MUSL_LOCALES_LANG_VERSION}" \
     tzdata="${TZDATA_VERSION}" \
     zlib="${ZLIB_VERSION}"; \
    rm -rf /var/cache/apk/*

FROM java_base AS prepare
SHELL ["/bin/sh", "-o", "pipefail", "-c"]

ARG LT_VERSION
ARG JAVA_VERSION
ARG MAVEN_VERSION

ENV JAVA_HOME=/opt/java/openjdk \
    JAVA_VERSION=${JAVA_VERSION}

# renovate: datasource=repology depName=alpine_3_24/7zip versioning=loose
ARG SEVEN_ZIP_VERSION="26.01-r0"

RUN set -eux; \
    apk add --no-cache binutils 7zip="${SEVEN_ZIP_VERSION}"; \
    rm -rf /var/cache/apk/*

ARG TARGETARCH
# hadolint ignore=SC3060,DL4006,SC2086
RUN set -eux; \
    RELEASE_PATH="${JAVA_VERSION/+/%2B}"; \
    RELEASE_TYPE="${JAVA_VERSION%-*}"; \
    RELEASE_NUMBER="${JAVA_VERSION#*-}"; \
    RELEASE_NUMBER="${RELEASE_NUMBER/+/_}"; \
    case "${TARGETARCH}" in \
        amd64) JAVA_ARCH="x64" ;; \
        arm64) JAVA_ARCH="aarch64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
    esac; \
    URL="https://github.com/adoptium/temurin21-binaries/releases/download/${RELEASE_PATH}/OpenJDK21U-${RELEASE_TYPE}_${JAVA_ARCH}_alpine-linux_hotspot_${RELEASE_NUMBER}.tar.gz"; \
    CHKSUM=$(wget --quiet -O -  "${URL}.sha256.txt" | cut -d' ' -f1); \
    wget -O /tmp/openjdk.tar.gz ${URL}; \
    echo "${CHKSUM} */tmp/openjdk.tar.gz" | sha256sum -c -; \
    mkdir -p "${JAVA_HOME}"; \
    tar --extract \
        --file /tmp/openjdk.tar.gz \
        --directory "${JAVA_HOME}" \
        --strip-components 1 \
        --no-same-owner; \
    rm /tmp/openjdk.tar.gz;

# hadolint ignore=DL4006,SC2086
RUN set -eux; \
    URL="https://archive.apache.org/dist/maven/maven-${MAVEN_VERSION%%.*}/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"; \
    CHKSUM=$(wget --quiet -O - "${URL}.sha512"); \
    MAVEN_HOME=/opt/maven; \
    wget -O /tmp/maven.tar.gz ${URL}; \
    echo "${CHKSUM} */tmp/maven.tar.gz" | sha512sum -c -; \
    mkdir -p "${MAVEN_HOME}"; \
    tar --extract \
        --file /tmp/maven.tar.gz \
        --directory "${MAVEN_HOME}" \
        --strip-components 1 \
        --no-same-owner; \
    rm /tmp/maven.tar.gz;

COPY patches/ /patches/

# hadolint ignore=SC2086,DL3003
RUN set -eux; \
    apk add --upgrade --no-cache git xmlstarlet; \
    rm -rf /var/cache/apk/*; \
    git clone --depth 1 -b v${LT_VERSION} https://github.com/languagetool-org/languagetool.git /tmp/languagetool; \
    cd /tmp/languagetool; \
    if [ "${LT_VERSION}" == "6.7" ]; then \
        git apply --stat /patches/lt6_7_memory_leak_fix.patch; \
        git apply --check /patches/lt6_7_memory_leak_fix.patch; \
        git apply /patches/lt6_7_memory_leak_fix.patch; \
    fi ; \
    patch_property() { \
      local _xpath=${1}; \
      local _value=${2}; \
      xml edit --inplace --update "${_xpath}" --value "${_value}" /tmp/languagetool/pom.xml; \
    }; \
    if [ "${LT_VERSION}" == "6.8" ]; then \
        patch_property "//*[name()='ch.qos.logback.version']" "1.5.25"; \
        patch_property "//*[name()='jackson.version']" "2.18.6"; \
        patch_property "//*[name()='org.apache.opennlp.opennlp-tools.version']" "2.5.9"; \
        patch_property "//*[name()='io.opentelemetry.version']" "1.62.0"; \
        patch_property "//*[name()='io.lettuce.version']" "7.6.0.RELEASE"; \
    fi ; \
    /opt/maven/bin/mvn  \
      --file /tmp/languagetool/pom.xml \
      --projects languagetool-standalone \
      --also-make package \
      -DskipTests \
      --threads 2C \
      --quiet; \
    7z x "/tmp/languagetool/languagetool-standalone/target/LanguageTool-${LT_VERSION}.zip" -o"/" -bb1 -bso1 -bse1 -bsp1 -y; \
    mv /LanguageTool-*/ "/languagetool"; \
	cd "/languagetool"; \
    ${JAVA_HOME}/bin/jar xf languagetool-server.jar logback.xml; \
    rm -r "/tmp/languagetool"; \
    update_maven_dependency() { \
      local _URL=${1}; \
      local _FILENAME=${_URL##*/}; \
      local _FILENAME=${_FILENAME%\-*}.jar; \
      wget "${_URL}" -O /languagetool/libs/${_FILENAME}; \
    }; \
    export NETTY_VERSION=4.2.15.Final ; \
    update_maven_dependency https://repo1.maven.org/maven2/io/netty/netty-buffer/${NETTY_VERSION}/netty-buffer-${NETTY_VERSION}.jar; \
    update_maven_dependency https://repo1.maven.org/maven2/io/netty/netty-codec-dns/${NETTY_VERSION}/netty-codec-dns-${NETTY_VERSION}.jar; \
    update_maven_dependency https://repo1.maven.org/maven2/io/netty/netty-codec/${NETTY_VERSION}/netty-codec-${NETTY_VERSION}.jar; \
    update_maven_dependency https://repo1.maven.org/maven2/io/netty/netty-common/${NETTY_VERSION}/netty-common-${NETTY_VERSION}.jar; \
    update_maven_dependency https://repo1.maven.org/maven2/io/netty/netty-handler/${NETTY_VERSION}/netty-handler-${NETTY_VERSION}.jar; \
    update_maven_dependency https://repo1.maven.org/maven2/io/netty/netty-resolver-dns/${NETTY_VERSION}/netty-resolver-dns-${NETTY_VERSION}.jar; \
    update_maven_dependency https://repo1.maven.org/maven2/io/netty/netty-resolver/${NETTY_VERSION}/netty-resolver-${NETTY_VERSION}.jar; \
    update_maven_dependency https://repo1.maven.org/maven2/io/netty/netty-transport-native-unix-common/${NETTY_VERSION}/netty-transport-native-unix-common-${NETTY_VERSION}.jar; \
    update_maven_dependency https://repo1.maven.org/maven2/io/netty/netty-transport/${NETTY_VERSION}/netty-transport-${NETTY_VERSION}.jar; \
    echo "patches applied"

RUN set -eux; \
    LT_DEPS=$("${JAVA_HOME}/bin/jdeps" \
        --print-module-deps \
        --ignore-missing-deps \
        --recursive \
        --multi-release 21 \
        --class-path="/languagetool/libs/*" \
        --module-path="/languagetool/libs/*" \
        /languagetool/languagetool-server.jar); \
    "${JAVA_HOME}/bin/jlink" \
        --add-modules "${LT_DEPS}" \
        --strip-debug \
        --no-man-pages \
        --no-header-files \
        --output /opt/java/customjre

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION} AS go_build
ARG TARGETARCH
WORKDIR /src
COPY entrypoint/go.mod ./
COPY entrypoint/cmd/ cmd/
COPY entrypoint/internal/ internal/
RUN go mod tidy && \
    CGO_ENABLED=0 GOOS=linux GOARCH=${TARGETARCH} go build -ldflags="-s -w" -o /entrypoint ./cmd/entrypoint

FROM java_base

# renovate: datasource=repology depName=alpine_3_24/libstdc++ versioning=loose
ARG LIBSTDCPP_VERSION="15.2.0-r5"
# renovate: datasource=repology depName=alpine_3_24/gcompat versioning=loose
ARG GCOMPAT_VERSION="1.1.0-r4"
# renovate: datasource=repology depName=alpine_3_24/tini versioning=loose
ARG TINI_VERSION="0.19.0-r3"
# renovate: datasource=repology depName=alpine_3_24/fasttext versioning=loose
ARG FASTTEXT_VERSION="0.9.2-r3"
# renovate: datasource=repology depName=alpine_3_24/nss_wrapper versioning=loose
ARG NSS_WRAPPER_VERSION="1.1.12-r1"

RUN set -eux; \
    apk add --no-cache \
      libstdc++="${LIBSTDCPP_VERSION}" \
      gcompat="${GCOMPAT_VERSION}" \
      tini="${TINI_VERSION}" \
      fasttext="${FASTTEXT_VERSION}" \
      nss_wrapper="${NSS_WRAPPER_VERSION}"; \
    rm -f /var/cache/apk/*

RUN set -eux; \
    addgroup -g 783 languagetool; \
    adduser -u 783 -S -D -G languagetool -H languagetool; \
    mkdir -p /ngrams /fasttext

COPY --from=prepare /languagetool/ /languagetool
COPY --from=prepare /opt/java/customjre/ /opt/java/customjre
COPY --from=go_build /entrypoint /entrypoint

ENV JAVA_HOME=/opt/java/customjre \
    langtool_languageModel=/ngrams \
    langtool_fasttextBinary=/usr/bin/fasttext \
    langtool_fasttextModel=/fasttext/lid.176.bin \
    download_ngrams_for_langs=none \
    MAP_UID=783 \
    MAP_GID=783 \
    LOG_LEVEL=INFO \
    LOGBACK_CONFIG=./logback.xml \
    DISABLE_FILE_OWNER_FIX=false \
    DISABLE_FASTTEXT=false \
    LISTEN_PORT=8081 \
    CONTAINER_MODE=default

ENV PATH=${JAVA_HOME}/bin:${PATH}

WORKDIR /languagetool

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s \
  CMD ["/entrypoint", "healthcheck"]

EXPOSE ${LISTEN_PORT}

# The entrypoint binary performs the privilege drop at runtime via syscall.Setuid/Setgid.
# A static USER instruction would break the privileged startup mode needed for ownership fixes.
# trivy:ignore:AVD-DS-0002
#checkov:skip=CKV_DOCKER_3:privilege drop is handled by the entrypoint binary at runtime
ENTRYPOINT ["/sbin/tini", "-g", "-e", "143", "--", "/entrypoint"]

ARG IMAGE_VERSION
ARG IMAGE_CREATED

LABEL org.opencontainers.image.title="meyay/languagetool"
LABEL org.opencontainers.image.description="Minimal Docker Image for LanguageTool with fasttext support and automatic ngrams download"
LABEL org.opencontainers.image.version="${IMAGE_VERSION}"
LABEL org.opencontainers.image.created="${IMAGE_CREATED}"
LABEL org.opencontainers.image.licenses="LGPL-2.1"
LABEL org.opencontainers.image.documentation="https://github.com/meyayl/docker-languagetool"
LABEL org.opencontainers.image.source="https://github.com/meyayl/docker-languagetool"
LABEL org.opencontainers.image.url="https://github.com/languagetool-org/languagetool"
