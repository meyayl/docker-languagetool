# LanguageTool Docker Image

> [LanguageTool](https://www.languagetool.org/) is an Open Source proofreading software for English, French, German, Polish, Russian, and [more than 20 other languages](https://languagetool.org/languages/). It finds many errors that a simple spell checker cannot detect.

The source repository can be found on [GitHub](https://github.com/meyayl/docker-languagetool).
The Docker Hub repository can be found on [Docker Hub](https://hub.docker.com/r/meyay/languagetool).

## Features

- Built directly from [LanguageTool repository tags](https://github.com/languagetool-org/languagetool/tags) since official release ZIPs were [discontinued after v6.6](https://github.com/languagetool-org/languagetool/blob/master/languagetool-standalone/CHANGES.md#66-2025-03-27)
- Built on latest Alpine 3.24 base image
- Multi-arch: supports `linux/amd64` and `linux/arm64`
- Custom Eclipse Temurin 21 JRE (optimized with required modules only)
- Uses `tini` to handle container signals properly
- includes `fasttext`
- container starts as privileged user (=root) and executes LanguageTool as unprivileged user (default)
  - optional: container fixes folder ownership for ngrams and fasttext folders (default)
  - optional: support user mapping (make sure to check MAP_UID and MAP_GID below)
  - optional: works with read-only filesystem (uses nss_wrapper for user mapping)
- container can be started as unprivileged user instead of root user
  - optional: works with read-only filesystem
- optional: downloads ngram language modules if configured (if they don't already exist)
- optional: downloads fasttext module (if it doesn't already exist)
- optional: allows to set log level

## Setup

The following subsections show usage examples.
An example compose file can be downloaded from [docker-compose.yml](https://raw.githubusercontent.com/meyayl/docker-languagetool/main/docker-compose.yml).

### Start container as root user with read-only filesystem, start LanguageTool as MAP_UID:MAP_GID

Start the container as root user with all required capabilities to fix file ownership, and execute LanguageTool as unprivileged user.

#### Docker CLI Usage

```sh
docker run -d \
  --name languagetool \
  --restart unless-stopped \
  --cap-drop ALL \
  --cap-add CAP_CHOWN \
  --cap-add CAP_DAC_OVERRIDE \
  --cap-add CAP_SETUID \
  --cap-add CAP_SETGID \
  --security-opt no-new-privileges \
  --publish 8081:8081 \
  --env download_ngrams_for_langs=en \
  --env MAP_UID=783 \
  --env MAG_GID=783 \
  --read-only \
  --tmpfs /tmp:exec \
  --volume $PWD/ngrams:/ngrams \
  --volume $PWD/fasttext:/fasttext \
  meyay/languagetool:latest
```

#### Docker Compose Usage

```yaml
---
services:
  languagetool:
    image: meyay/languagetool:latest
    container_name: languagetool
    restart: unless-stopped
    read_only: true
    tmpfs:
      - /tmp:exec
    cap_drop:
      - ALL
    cap_add:
      - CAP_CHOWN
      - CAP_DAC_OVERRIDE
      - CAP_SETUID
      - CAP_SETGID
    security_opt:
      - no-new-privileges
    ports:
      - 8081:8081
    environment:
      download_ngrams_for_langs: en
      MAP_UID: 783
      MAP_GID: 783
    volumes:
      - ./ngrams:/ngrams
      - ./fasttext:/fasttext
```

### Start container as unprivileged user with read-only filesystem

Start the container as unprivileged user specified by the `--user` argument.
The container will neither try to fix file ownership, nor does it require any additional capabilities.

You need to make sure the directories bound as volume do exist, and are owned by the same user and/or group specified in the `--user`argument!

This is the recommended way to run the container.

#### Docker CLI

```sh
docker run -d \
  --name languagetool \
  --restart unless-stopped \
  --cap-drop ALL \
  --security-opt no-new-privileges \
  --publish 8081:8081 \
  --env download_ngrams_for_langs=en \
  --user 783:783 \
  --read-only \
  --tmpfs /tmp:exec \
  --volume $PWD/ngrams:/ngrams \
  --volume $PWD/fasttext:/fasttext \
  meyay/languagetool:latest
```

#### Docker Compose

```yaml
---
services:
  languagetool:
    image: meyay/languagetool:latest
    container_name: languagetool
    restart: unless-stopped
    user: "783:783"
    read_only: true
    tmpfs:
      - /tmp:exec
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges
    ports:
      - 8081:8081
    environment:
      download_ngrams_for_langs: en
    volumes:
      - ./ngrams:/ngrams
      - ./fasttext:/fasttext
```

## Usage

You need to install and use one of the [add-ons](https://languagetool.org/services) and configure it to use the self-hosted LanguageTool server `http://{ip-of-your-docker-host}:{published host port}/v2`. The self-hosted LanguageTool server does not come with its own UI or supports user authentication!

NOTE: Some add-ons require https connections, which is not (and will not be) supported by this image. You will need to put a reverse proxy in front of it to take care of the TLS termination.

## Capabilities

If the container is started as unprivileged user, the capabilities `CAP_CHOWN` `CAP_DAC_OVERRIDE`, `CAP_SETUID` and `CAP_SETGID`, are not required, and can be omitted.
If the container is started as privileged user (default), and the environment variable `DISABLE_FILE_OWNER_FIX` is set to `true`, the capabilities `CAP_CHOWN` and `CAP_DAC_OVERRIDE` are not required and can be omitted.

## Ports

The self-hosted LanguageTool server in the container is listening on port `8081` by default.

It can be changed using the environment variable `LISTEN_PORT`.

## Volumes

| Required | Container Path | DESCRIPTION                                                                                                                                                                     |
| -------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| no       | /ngrams        | Location to store the ngram language models. If container is started as unprivileged user, make sure the host path is owned by the user and/or group that starts the container. |
| no       | /fasttext      | Location to store the fasttext model. If container is started as unprivileged user, make sure the host path is owned by the user and/or group that starts the container.        |
| yes      | /tmp           | Location to store the created logback.xml and config.property. Preferably a tmpfs mount with exec permissions.                                                                  |

Restrictions if only required volumes are used:

- privileged container: ngram language models and fasttext model will be written into the container filesystem.
- read-only filesystem: neither ngram language models, nor fasttext model can be used.
- unprivileged container: neither ngram language models, nor fasttext model can be used.

## Parameters

The environment parameters are split into two halves, separated by an equal or colon, the left-hand side represents the variable name (use it as is), the right-hand side the value (change if necessary).

| ENV                       | DEFAULT                 | DESCRIPTION                                                                                                                                                                                                                                            |
| ------------------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| download_ngrams_for_langs | none                    | Comma separated list of languages to download ngrams for. Skips download if the ngrams for that language already exist. Valid languages: `en`, `de`, `es`, `fr` and `nl`. Example value: `en,de`. See [Ngram language models](#ngram-language-models). |
| langtool_languageModel    | /ngrams                 | The base path to the ngram models. Only written into LanguageTool's config if the directory actually contains data; omitted if it's empty or missing. See [Ngram language models](#ngram-language-models).                                             |
| langtool_fasttextBinary   | /usr/local/bin/fasttext | Path to the fasttext binary. Change only if you want to test your own compiled binary. Don't forget to map it into the container as volume.                                                                                                            |
| langtool_fasttextModel    | /fasttext/lid.176.bin   | The container path to the fasttext model binary. If the variable is set, the fasttext model will be downloaded if doesn't exist yet.                                                                                                                   |
| langtool\_\*              |                         | An arbitrary LanguageTool configuration, consisting of the prefix `langtool_` and the key name as written in the config file. Execute `docker run -ti --rm meyay/languagetool help` to see the list of config options.                                 |
| JAVA_XMS                  | 256m                    | Minimum size of the Java heap space. Valid suffixes are `m` for megabytes and `g` for gigabytes.                                                                                                                                                       |
| JAVA_XMX                  | 1536m                   | Maximum size of the Java heap space. Valid suffixes are `m` for megabytes and `g` for gigabytes. Set a higher value if you experience OOM kills.                                                                                                       |
| JAVA_GC                   | ShenandoahGC            | Configure the garbage collector the JVM will use. Valid options are: `SerialGC`, `ParallelGC`, `ParNewGC`, `G1GC`, `ZGC`, `ShenandoahGC`                                                                                                               |
| JAVA_OPTS                 |                         | Set you own custom Java options for the JVM. This will render the other JAVA\_\* options useless.                                                                                                                                                      |
| LISTEN_PORT               | 8081                    | Set listen port of the self-hosted LanguageTool server inside the container.                                                                                                                                                                           |
| MAP_UID                   | 783                     | UID of the user inside the container that runs LanguageTool. If you encounter permission problems with your volumes, make sure to set the parameter to the UID of the host folder owner.                                                               |
| MAP_GID                   | 783                     | GID of the user inside the container that runs LanguageTool. If you encounter permission problems with your volumes, make sure to set the parameter to the GID of the host folder owner.                                                               |
| LOG_LEVEL                 | INFO                    | Set log level for LanguageTool. Valid options are: `TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`.                                                                                                                                                          |
| DISABLE_FILE_OWNER_FIX    | false                   | Disables file ownership fix, if set to `true`. Will be used implicitly, if the container is started with an upriviliged user. The Valid options are: `true`, anything else is treated as `false`.                                                      |
| DISABLE_FASTTEXT          | false                   | Disables fasttext, if set to `true`, neither the model is downloaded, nor fasttext enabled in LanguageTool. The Valid options are: `true`, anything else is treated as `false`.                                                                        |
| DEBUG_ENTRYPOINT          |                         | Enables debug logs, if set to `true`. The Valid options are: `true`, anything else is treated as `false`.                                                                                                                                              |
| CONTAINER_MODE            | default                 | Configure the containers behavior. Docker users use `default`. Kubernetes users can use `download-only` with initContainers, and start the main container with `default`.                                                                              |

## Fasttext support

The image comes with the Alpine `fasttext` package. If it does not work for you, you can build a custom image to compile the `fasttext` binary using CPU optimizations your CPU actually understands (supports both `amd64` and `arm64`):

```shell
git clone  https://github.com/meyayl/docker-languagetool.git
cd docker-languagetool
sudo docker build -t meyay/languagetool:latest -f Dockerfile.fasttext .
```

As alternative method, `sudo make docker_build` can be used to build your custom image.

Once the image is build, you can `docker compose up -d` like you would do with the images hosted on Docker Hub.

> NOTE: Synology users can find a git package in the [SynoCommunity](https://synocommunity.com) repository.

## Ngram language models

LanguageTool can use [n-gram data](https://dev.languagetool.org/finding-errors-using-n-gram-data) to improve suggestions (e.g. the confusion rule). The `/ngrams` volume is where that data lives, and two variables control it:

- `download_ngrams_for_langs` (default `none`): comma-separated list of languages (`en`, `de`, `es`, `fr`, `nl`) the container should auto-download ngram models for on startup, if they don't already exist under `/ngrams`.
- `langtool_languageModel` (default `/ngrams`): the base directory LanguageTool is told to load ngram models from, passed through to its `config.properties` as the `languageModel` key.

The entrypoint only writes the `languageModel` key into `config.properties` when `langtool_languageModel`'s directory actually contains data (i.e. is not empty and not missing). If the directory is empty or doesn't exist, the key is omitted entirely, rather than being written pointing at nothing.

This matters because LanguageTool's HTTP server silently disables spelling-mistake matches (`MORFOLOGIK_RULE_*`, `GERMAN_SPELLER_RULE`, etc.) for a language whenever `languageModel` is configured but resolves to a directory without usable ngram data for it — it returns `"matches": []` with a `200 OK`, no error or warning ([#179](https://github.com/meyayl/docker-languagetool/issues/179)).
This is a LanguageTool server behavior, not something specific to this image, and grammar/pattern rules are unaffected. Since ngram downloads are optional and large (multi-GB per language), most deployments don't have them — omitting the empty `languageModel` key avoids silently breaking spelling checks for anyone who hasn't opted into `download_ngrams_for_langs`.

If you mount your own pre-downloaded ngram data at `/ngrams` (or wherever `langtool_languageModel` points), it is used as expected regardless of `download_ngrams_for_langs` — the directory-emptiness check, not the download setting, decides whether `languageModel` is written.

## Custom spelling files

Each language's word lists live at `/languagetool/org/languagetool/resource/<language-code>/hunspell/` inside the image.
To add words that should never be flagged as spelling mistakes (e.g. product names, jargon, or names in your organization),
bind-mount a text file (one word per line) over the `spelling_custom.txt` file for the language(s) you use:

```yaml
volumes:
  - ./custom-words-en.txt:/languagetool/org/languagetool/resource/en/hunspell/spelling_custom.txt:ro
  - ./custom-words-de.txt:/languagetool/org/languagetool/resource/de/hunspell/spelling_custom.txt:ro
```

The same pattern applies to `prohibit_custom.txt` (words that should always be flagged) under the same `<language-code>/hunspell/` directory. Replace `en`/`de` with the language code(s) you need (e.g. `es`, `fr`, `nl`); see the [LanguageTool source](https://github.com/languagetool-org/languagetool/tree/master/languagetool-language-modules) for the full list of supported languages and their codes.

See LanguageTool's [Hunspell support documentation](https://dev.languagetool.org/hunspell-support) for the word list file format (one word per line) and how `spelling.txt`/`spelling_custom.txt` (ignored words) differ from `prohibit.txt`/`prohibit_custom.txt` (words always flagged as incorrect).

> NOTE: This requires image version `6.8-8` or later. Earlier versions did not reliably load bind-mounted custom spelling files because the working directory was missing from the Java classpath ([#177](https://github.com/meyayl/docker-languagetool/issues/177)).

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full release history.
