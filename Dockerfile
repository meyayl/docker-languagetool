FROM alpine:3.18.4 as base

FROM base as java_base

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

RUN set -eux; \
    apk add --no-cache libretls musl-locales musl-locales-lang tzdata zlib unzip; \
    rm -rf /var/cache/apk/*

FROM java_base as prepare
SHELL ["/bin/sh", "-o", "pipefail", "-c"]

ARG LT_VERSION=6.3

ENV JAVA_HOME=/opt/java/openjdk \
    JAVA_VERSION=jdk-17.0.8.1+1

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
    URL="https://github.com/adoptium/temurin17-binaries/releases/download/${RELEASE_PATH}/OpenJDK17U-${RELEASE_TYPE}_x64_alpine-linux_hotspot_${RELEASE_NUMBER}.tar.gz"; \
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
    wget -O /tmp/LanguageTool-${LT_VERSION}.zip https://www.languagetool.org/download/LanguageTool-${LT_VERSION}.zip; \
    unzip "/tmp/LanguageTool-${LT_VERSION}.zip"; \
    mv "/LanguageTool-${LT_VERSION}" "/languagetool"; \
	cd "/languagetool"; \
    ${JAVA_HOME}/bin/jar xf languagetool-server.jar logback.xml; \
    rm "/tmp/LanguageTool-${LT_VERSION}.zip" 

RUN set -eux; \
    LT_DEPS=$("${JAVA_HOME}/bin/jdeps" \
        --print-module-deps \
        --ignore-missing-deps \
        --recursive \
        --multi-release 17 \
        --class-path="/languagetool/libs/*" \
        --module-path="/languagetool/libs/*" \
        /languagetool/languagetool-server.jar); \
    "${JAVA_HOME}/bin/jlink" \
        --add-modules "${LT_DEPS}" \
        --strip-debug \
        --no-man-pages \
        --no-header-files \
        --compress=2 \
        --output /opt/java/customjre


FROM base as fasttext

SHELL ["/bin/sh", "-o", "pipefail", "-c"]

RUN set -eux; \
    apk add --no-cache git build-base upx; \
    rm -rf /var/cache/apk/*

RUN set -eux; \
    git clone https://github.com/facebookresearch/fastText.git; \
    make -C fastText;\
    upx -5 -o /fastText/fasttext-upx /fastText/fasttext


FROM java_base

RUN set -eux; \
    apk add --no-cache bash shadow libstdc++ gcompat su-exec tini xmlstarlet; \
    rm -f /var/cache/apk/*

RUN set -eux; \
    groupmod --gid 783 --new-name languagetool users; \
    adduser -u 783 -S languagetool -G languagetool

COPY --from=prepare /languagetool/ /languagetool
COPY --from=prepare /opt/java/customjre/ /opt/java/customjre
COPY --from=fasttext /fastText/fasttext-upx /usr/local/bin/fasttext

ENV JAVA_HOME=/opt/java/customjre \
    langtool_fasttextBinary=/usr/local/bin/fasttext \
    download_ngrams_for_langs=none \
    MAP_UID=783 \
    MAP_GID=783 \
    LOG_LEVEL=INFO \
    LOGBACK_CONFIG=./logback.xml

ENV PATH=${JAVA_HOME}/bin:${PATH}

WORKDIR /languagetool

COPY --chown=languagetool entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s CMD wget --quiet --post-data "language=en-US&text=a simple test" -O - http://localhost:8010/v2/check > /dev/null 2>&1  || exit 1
EXPOSE 8010

ENTRYPOINT ["/sbin/tini", "-g", "-e 143", "--", "/entrypoint.sh"]
