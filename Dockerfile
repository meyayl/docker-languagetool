ARG IMAGE_VERSION="6.7-7"
ARG IMAGE_CREATED="2026-02-18"
# renovate: datasource=github-tags depName=languagetool-org/languagetool versioning=loose
ARG LT_VERSION="6.7"
# renovate: datasource=github-tags depName=adoptium/temurin21-binaries versioning=loose
ARG JAVA_VERSION="jdk-21.0.10+7"
# renovate: datasource=github-tags depName=apache/maven versioning=loose
ARG MAVEN_VERSION="3.9.12"
FROM alpine:3.23.3 AS base

FROM base AS java_base

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# renovate: datasource=repology depName=alpine_3_23/libretls versioning=loose
ARG LIBRETLS_VERSION="3.8.1-r0"
# renovate: datasource=repology depName=alpine_3_23/musl-locales versioning=loose
ARG MUSL_LOCALES_VERSION="0.1.0-r1"
# renovate: datasource=repology depName=alpine_3_23/musl-locales-lang versioning=loose
ARG MUSL_LOCALES_LANG_VERSION="0.1.0-r1"
# renovate: datasource=repology depName=alpine_3_23/tzdata versioning=loose
ARG TZDATA_VERSION="2025c-r0"
# renovate: datasource=repology depName=alpine_3_23/zlib versioning=loose
ARG ZLIB_VERSION="1.3.1-r2"
# renovate: datasource=repology depName=alpine_3_23/7zip versioning=loose
ARG SEVEN_ZIP_VERSION="25.01-r0"

RUN set -eux; \
    apk add --upgrade --no-cache \
     libretls="${LIBRETLS_VERSION}" \
     musl-locales="${MUSL_LOCALES_VERSION}" \
     musl-locales-lang="${MUSL_LOCALES_LANG_VERSION}" \
     tzdata="${TZDATA_VERSION}" \
     zlib="${ZLIB_VERSION}" \
     7zip="${SEVEN_ZIP_VERSION}"; \
    rm -rf /var/cache/apk/*

FROM java_base AS prepare
SHELL ["/bin/sh", "-o", "pipefail", "-c"]

ARG LT_VERSION
ARG JAVA_VERSION
ARG MAVEN_VERSION

ENV JAVA_HOME=/opt/java/openjdk \
    JAVA_VERSION=${JAVA_VERSION}

RUN set -eux; \
    apk add --no-cache binutils; \
    rm -rf /var/cache/apk/*

# hadolint ignore=SC3060
# hadolint ignore=DL4006
RUN set -eux; \
    RELEASE_PATH="${JAVA_VERSION/+/%2B}"; \
    RELEASE_TYPE="${JAVA_VERSION%-*}"; \
    RELEASE_NUMBER="${JAVA_VERSION#*-}"; \
    RELEASE_NUMBER="${RELEASE_NUMBER/+/_}"; \
    URL="https://github.com/adoptium/temurin21-binaries/releases/download/${RELEASE_PATH}/OpenJDK21U-${RELEASE_TYPE}_x64_alpine-linux_hotspot_${RELEASE_NUMBER}.tar.gz"; \
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

RUN set -eux; \
    URL="https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"; \
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

# hadolint ignore=SC2086 - we need file globbing when deleting apk packages, and moving the LanguageTool-${LT_VERSION}
# hadolint ignore=DL3003 - we need to change into directories withing the RUN instruction, bjt don't want extra layers
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
    patch_property "//*[name()='ch.qos.logback.version']" "1.5.25"; \
    patch_property "//*[name()='jackson.version']" "2.18.6"; \
    /opt/maven/bin/mvn  \
     \--file /tmp/languagetool/pom.xml \
      --projects languagetool-standalone \
      --also-make package \
      -DskipTests \
      --threads 1C \
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
    update_maven_dependency https://repo1.maven.org/maven2/io/netty/netty-buffer/4.1.131.Final/netty-buffer-4.1.131.Final.jar; \
    update_maven_dependency https://repo1.maven.org/maven2/io/netty/netty-codec-dns/4.1.131.Final/netty-codec-dns-4.1.131.Final.jar; \
    update_maven_dependency https://repo1.maven.org/maven2/io/netty/netty-codec/4.1.131.Final/netty-codec-4.1.131.Final.jar; \
    update_maven_dependency https://repo1.maven.org/maven2/io/netty/netty-common/4.1.131.Final/netty-common-4.1.131.Final.jar; \
    update_maven_dependency https://repo1.maven.org/maven2/io/netty/netty-handler/4.1.131.Final/netty-handler-4.1.131.Final.jar; \
    update_maven_dependency https://repo1.maven.org/maven2/io/netty/netty-resolver-dns/4.1.131.Final/netty-resolver-dns-4.1.131.Final.jar; \
    update_maven_dependency https://repo1.maven.org/maven2/io/netty/netty-resolver/4.1.131.Final/netty-resolver-4.1.131.Final.jar; \
    update_maven_dependency https://repo1.maven.org/maven2/io/netty/netty-transport-native-unix-common/4.1.131.Final/netty-transport-native-unix-common-4.1.131.Final.jar; \
    update_maven_dependency https://repo1.maven.org/maven2/io/netty/netty-transport/4.1.131.Final/netty-transport-4.1.131.Final.jar;

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

FROM java_base

# renovate: datasource=repology depName=alpine_3_23/bash versioning=loose
ARG BASH_VERSION="5.3.3-r1"
# renovate: datasource=repology depName=alpine_3_23/shadow versioning=loose
ARG SHADOW_VERSION="4.18.0-r0"
# renovate: datasource=repology depName=alpine_3_23/libstdc++ versioning=loose
ARG LIBSTDCPP_VERSION="15.2.0-r2"
# renovate: datasource=repology depName=alpine_3_23/gcompat versioning=loose
ARG GCOMPAT_VERSION="1.1.0-r4"
# renovate: datasource=repology depName=alpine_3_23/su-exec versioning=loose
ARG SU_EXEC_VERSION="0.3-r0"
# renovate: datasource=repology depName=alpine_3_23/tini versioning=loose
ARG TINI_VERSION="0.19.0-r3"
# renovate: datasource=repology depName=alpine_3_23/xmlstarlet versioning=loose
ARG XMLSTARLET_VERSION="1.6.1-r2"
# renovate: datasource=repology depName=alpine_3_23/fasttext versioning=loose
ARG FASTTEXT_VERSION="0.9.2-r1"
# renovate: datasource=repology depName=alpine_3_23/nss_wrapper versioning=loose
ARG NSS_WRAPPER_VERSION="1.1.12-r1"

RUN set -eux; \
    apk add --no-cache \
      bash="${BASH_VERSION}" \
       shadow="${SHADOW_VERSION}" \
       libstdc++="${LIBSTDCPP_VERSION}" \
       gcompat="${GCOMPAT_VERSION}" \
       su-exec="${SU_EXEC_VERSION}" \
       tini="${TINI_VERSION}" \
       xmlstarlet="${XMLSTARLET_VERSION}" \
       fasttext="${FASTTEXT_VERSION}" \
       nss_wrapper="${NSS_WRAPPER_VERSION}"; \
    rm -f /var/cache/apk/*

RUN set -eux; \
    groupmod --gid 783 --new-name languagetool users; \
    adduser -u 783 -S languagetool -G languagetool -H; \
    mkdir -p /ngrams /fasttext

COPY --from=prepare /languagetool/ /languagetool
COPY --from=prepare /opt/java/customjre/ /opt/java/customjre

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
  CMD wget --quiet --output-document - http://localhost:${LISTEN_PORT}/v2/healthcheck > /dev/null 2>&1  || exit 1

EXPOSE ${LISTEN_PORT}

COPY --chmod=755 entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/sbin/tini", "-g", "-e", "143", "--", "/entrypoint.sh"]

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
