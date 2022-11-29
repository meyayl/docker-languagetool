FROM alpine:3.17.0 as build
RUN apk add git build-base --no-cache
RUN set -eux; \
    git clone https://github.com/facebookresearch/fastText.git; \
    make -C fastText;\
    git clone https://github.com/ncopa/su-exec; \
    make -C su-exec;

FROM alpine:3.17.0
ARG VERSION=5.9

RUN set -eux; \
    apk add --update-cache \
      bash \
      curl \
      unzip \
      libstdc++ \
      shadow \
      openjdk17-jre-headless; \
    rm -f /var/cache/apk/*

RUN set -eux; \ 
    groupmod --gid 783 --new-name languagetool users; \
    adduser -u 783 -S languagetool -G languagetool

RUN curl --location --output /tmp/LanguageTool-${VERSION}.zip https://www.languagetool.org/download/LanguageTool-${VERSION}.zip; \
    unzip /tmp/LanguageTool-${VERSION}.zip; \
    rm /tmp/LanguageTool-${VERSION}.zip; \
    mv /LanguageTool-${VERSION} /LanguageTool; \
    chown languagetool:languagetool -R /LanguageTool

COPY --from=build /fastText/fasttext /usr/local/bin/fasttext
COPY --from=build /su-exec/su-exec /usr/local/bin/su-exec

ENV langtool_fasttextBinary=/usr/local/bin/fasttext \
    download_ngrams_for_langs=none \
    MAP_UID=783 \
    MAP_GID=783

WORKDIR /LanguageTool

COPY --chown=languagetool entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

HEALTHCHECK --interval=10s --timeout=8s --start-period=10s CMD curl --fail --data "language=en-US&text=a simple test" http://localhost:8010/v2/check || exit 1
EXPOSE 8010

ENTRYPOINT ["/entrypoint.sh"]

