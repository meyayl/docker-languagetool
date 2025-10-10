ARG LT_VERSION=6.7
ARG JAVA_VERSION=jdk-21.0.8+9
ARG MAVEN_VERSION=3.9.11
FROM alpine:3.22.2 AS base

FROM base AS java_base

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

RUN set -eux; \
    apk add --upgrade --no-cache libretls musl-locales musl-locales-lang tzdata zlib; \
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
        --no-same-owner \
    ; \
    rm /tmp/openjdk.tar.gz;

RUN set -eux; \
    URL="https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" ; \
    CHKSUM=$(wget --quiet -O - "${URL}.sha512") ; \
    MAVEN_HOME=/opt/maven : \
    echo "b" ;\
    wget -O /tmp/maven.tar.gz ${URL} ; \
    echo "c" ;\
    echo "${CHKSUM} */tmp/maven.tar.gz" | sha512sum -c - ; \
    mkdir -p "${MAVEN_HOME}"; \
    echo "d" ;\
    tar --extract \
        --file /tmp/maven.tar.gz \
        --directory "${MAVEN_HOME}" \
        --strip-components 1 \
        --no-same-owner \
    ; \
    echo "d" ;\
    rm /tmp/maven.tar.gz;

RUN set -eux; \
    apk add --upgrade --no-cache git; \
    rm -rf /var/cache/apk/* ;\
    git clone --depth 1 -b v${LT_VERSION} https://github.com/languagetool-org/languagetool.git /tmp/languagetool ; \
    /opt/maven/bin/mvn --file /tmp/languagetool/pom.xml --projects languagetool-standalone --also-make package -DskipTests --quiet; \
    unzip "/tmp/languagetool/languagetool-standalone/target/LanguageTool-${LT_VERSION}.zip" -d "/"; \
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
    update_maven_dependency https://repo1.maven.org/maven2/io/netty/netty-codec/4.1.127.Final/netty-codec-4.1.127.Final.jar;

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

RUN set -eux; \
    apk add --no-cache bash shadow libstdc++ gcompat su-exec tini xmlstarlet fasttext nss_wrapper; \
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

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s CMD wget --quiet --output-document - http://localhost:${LISTEN_PORT}/v2/healthcheck > /dev/null 2>&1  || exit 1
EXPOSE ${LISTEN_PORT}

COPY --chmod=755 entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/sbin/tini", "-g", "-e", "143", "--", "/entrypoint.sh"]

LABEL org.opencontainers.image.title="meyay/languagetool"
LABEL org.opencontainers.image.description="Minimal Docker Image for LanguageTool with fasttext support and automatic ngrams download"
LABEL org.opencontainers.image.version="6.7-1"
LABEL org.opencontainers.image.created="2025-10-10"
LABEL org.opencontainers.image.licenses="LGPL-2.1"
LABEL org.opencontainers.image.documentation="https://github.com/meyayl/docker-languagetool"
LABEL org.opencontainers.image.source="https://github.com/meyayl/docker-languagetool"
LABEL org.opencontainers.image.url="https://github.com/languagetool-org/languagetool"
