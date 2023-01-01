# LanguageTool

> [LanguageTool](https://www.languagetool.org/) is an Open Source proofreading software for English, French, German, Polish, Russian, and [more than 20 other languages](https://languagetool.org/languages/). It finds many errors that a simple spell checker cannot detect.

The source repository can be found [here](https://github.com/meyayl/docker-languagetool).

About this image:

- Uses official [release zip](https://languagetool.org/download/)
- Uses the latest Alpine 3.17 base image
- Uses custom Eclipse Temurin 17 JRE limited to modules required by the current LanguageTool release
- includes `fasttext`
- includes `su-exec`
  - container starts as root and executes languagetool as restricted user using `exec su-exec`
  - container fixes folder ownership for ngrams and fasttext folders
- Entrypoint uses `tini` to suppress the container exiting with status code 143 (LanguageTool does not handle SIGTERM as it should)
- optional: downloads ngram language modules if configured (if they don't already exist)
- optional: downloads fasttext module (if it doesn't already exist)
- optional: user mapping (make sure to check MAP_UID and MAP_GID below)

## Setup

### Docker CLI Usage

```sh
docker run -d \
  --name languagetool \
  --restart always \
  --cap-drop ALL \
  --cap-add CAP_SETUID \
  --cap-add CAP_SETGID \
  --security-opt no-new-privileges \
  --publish 8010:8010 \
  --env download_ngrams_for_langs=en \
  --env langtool_languageModel=/ngrams \
  --env langtool_fasttextModel=/fasttext/lid.176.bin \
  --volume $PWD/ngrams:/ngrams \
  --volume $PWD/fasttext:/fasttext \
  meyay/languagetool:latest
```

## Docker Compose Usage

```yaml
---
version: "3.8"

services:
  languagetool:
    image: meyay/languagetool:latest
    container_name: languagetool
    restart: always
    cap_drop:
      - ALL
    cap_add:
      - CAP_SETUID
      - CAP_SETGID
    security_opt:
      - no-new-privileges
    ports:
      - 8010:8010
    environment:
      download_ngrams_for_langs: en
      langtool_languageModel: /ngrams
      langtool_fasttextModel: /fasttext/lid.176.bin
    volumes:
      - ./ngrams:/ngrams
      - ./fasttext:/fasttext
```

An example compose file can be downloaded from [here](https://raw.githubusercontent.com/meyayl/docker-languagetool/main/docker-compose.yml).

## Parameters

The environment parameters are split into two halves, separated by an equal, the left-hand side represents the variable names (use them as is) the right-hand side the value (change if necessary).

| ENV| DEFAULT | DESCRIPTION |
| ------ | ------ | ------ |
| download_ngrams_for_langs | none | Optional: Comma separated list of languages to download ngrams for. Skips download if the ngrams for that language already exist. Valid languages: `en`, `de`, `es`, `fr` and `nl`. Example value: `en,de` |
| langtool_languageModel | /ngrams | Optional: The base path to the ngrams models. |
| langtool_fasttextBinary | /usr/local/bin/fasttext | Optional: Path to the fasttext binary. Change only if you want to test your own compiled binary. Don't forget to map it into the container as volume. |
| langtool_fasttextModel |  | Optional: The container path to the fasttext model binary. If the variable is set, the fasttext model will be downloaded if doesn't exist yet. |
| langtool_*|  |  Optional: An arbitrary languagetool configuration, consisting of the prefix `langtool_` and the key name as written in the config file. Execute `docker run -ti --rm meyay/languagetool help` to see the list of config options |
| JAVA_XMS | 256m | Optional: Minimum size of the Java heap space. Valid suffixes are `m` for megabytes and `g` for gigabytes.|
| JAVA_XMX | 1024m | Optional: Maximum size of the Java heap space. Valid suffixes are `m` for megabytes and `g` for gigabytes. Set a higher value if you experience OOM kills, but do not use more than 1/4 of the host memory! |
| JAVA_GC | SerialGC | Optional: Configure the garbage collector the JVM will use. Valid options are: `SerialGC`, `ParallelGC`, `ParNewGC`, `G1GC`, `ZGC` |
| JAVA_OPTS | | Optional: Set you own custom Java options for the JVM. This will render the other JAVA_* options useless. |
| MAP_UID | 783 | Optional: UID of the user inside the container that runs LanguageTool. If you encounter permission problems with your volumes, make sure to set the parameter to the UID of the host folder owner. |
| MAP_GID | 783 | Optional: GID of the user inside the container that runs LanguageTool. If you encounter permission problems with your volumes, make sure to set the parameter to the GID of the host folder owner. |

## Changelog

| Date | Tag | Change |
|---|---|---|
| 2023-01-01| 6.0-2 | - Add  alpine package `gcompat` to satisfy `ld-linux-x86-64.so.2` dependency.|
| ~~2022-12-29~~</br>2023-01-01| ~~6.0-1~~ | ~~- Upgrade to languagetool 6.0~~</br> - Removed tag due to ClassPath exception.|
| 2022-12-07 | 5.9-7 | - Fix health check command |
| 2022-12-04 | 5.9-6 | - Add `help` comfmand to display languagetool configuration items to be used with `languagetool_*`|
| 2022-12-04 | 5.9-5 | - Switch to stripped down Eclipse Temurin 17 JRE </br> - Remove JVM argument `-XX:+UseStringDeduplication` except for G1GC </br> - Add `tini` to suppress exit code 143 </br> - Removed `curl` and switch to `wget` </br> - Print version info about Alpine and Eclipse Temurin during start |
| 2022-11-29 | 5.9-4 | - Update base image to Alpine 3.17.0 |
| 2022-11-24 | 5.9-3 | - Add support to configure garbage collector </br> - Add JVM argument `-XX:+UseStringDeduplication` </br> - Add support to pass custom JAVA_OPTS </br> - Change Java_Xm? variables to JAVA_XM? |
| 2022-11-12 | 5.9-2 | - Update base image to Alpine 3.16.3 |
| 2022-09-28 | 5.9-1 | - Update LanguageTool to 5.9 |
| 2022-09-10 | 5.8-2 | - Add user mapping support |
| 2022-09-10 | 5.8-1 | - Initial release with Alpine 3.16.2, LanguageTool 5.8 |
