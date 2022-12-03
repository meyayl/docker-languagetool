FROM alpine:3.17.0 as base

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

RUN set -eux; \
    apk add --no-cache fontconfig libretls musl-locales musl-locales-lang ttf-dejavu tzdata zlib; \
    rm -rf /var/cache/apk/*

FROM base as build

ENV JAVA_HOME=/opt/java/openjdk \
    JAVA_VERSION=jdk-17.0.5+8

RUN set -eux; \
    apk add --no-cache binutils git build-base upx; \
    rm -rf /var/cache/apk/*

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
    ${JAVA_HOME}/bin/jlink \
        --add-modules ALL-MODULE-PATH \
        --strip-debug \
        --no-man-pages \
        --no-header-files \
        --compress=2 \
        --output /opt/java/jre

RUN set -eux; \
    git clone https://github.com/facebookresearch/fastText.git; \
    make -C fastText;\
    upx -5 -o /fastText/fasttext-upx /fastText/fasttext

FROM base
ARG VERSION=5.9

RUN set -eux; \
    apk add --no-cache bash unzip shadow libstdc++ su-exec tini; \
    rm -f /var/cache/apk/*

RUN set -eux; \
    groupmod --gid 783 --new-name languagetool users; \
    adduser -u 783 -S languagetool -G languagetool

RUN set -eux; \
    wget -O /tmp/LanguageTool-${VERSION}.zip https://www.languagetool.org/download/LanguageTool-${VERSION}.zip; \
    unzip /tmp/LanguageTool-${VERSION}.zip; \
    rm /tmp/LanguageTool-${VERSION}.zip; \
    mv /LanguageTool-${VERSION} /languagetool; \
    chown languagetool:languagetool -R /languagetool

COPY --from=build /opt/java/jre/ /opt/java/jre
COPY --from=build /fastText/fasttext-upx /usr/local/bin/fasttext

ENV JAVA_HOME=/opt/java/jre \
    langtool_fasttextBinary=/usr/local/bin/fasttext \
    download_ngrams_for_langs=none \
    MAP_UID=783 \
    MAP_GID=783

ENV PATH=${JAVA_HOME}/bin:${PATH}

WORKDIR /languagetool

COPY --chown=languagetool entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s CMD curl --fail --data "language=en-US&text=a simple test" http://localhost:8010/v2/check || exit 1
EXPOSE 8010

ENTRYPOINT ["/sbin/tini", "-g", "-e 143", "--", "/entrypoint.sh"]
