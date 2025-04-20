# LanguageTool Docker Image

> [LanguageTool](https://www.languagetool.org/) is an Open Source proofreading software for English, French, German, Polish, Russian, and [more than 20 other languages](https://languagetool.org/languages/). It finds many errors that a simple spell checker cannot detect.

The source repository can be found [here](https://github.com/meyayl/docker-languagetool). <br/>
The Docker Hub repository can be found [here](https://hub.docker.com/r/meyay/languagetool).

## Features

- Uses official LanguageTool [release zip](https://languagetool.org/download/)
- Built on latest Alpine 3.21 base image
- Custom Eclipse Temurin 21 JRE (optimized with required modules only)
- Uses `tini` to handle container signals properly
- includes `fasttext`
- includes `su-exec`
- container starts as privileged user (=root) and executes LanguageTool as unprivileged user using `exec su-exec` (default)
  - optional: container fixes folder ownership for ngrams and fasttext folders (default)
  - optional: support user mapping (make sure to check MAP_UID and MAP_GID below)
  - optional: works with read-only filesystem (uses nss_wrapper for user mapping)
- container can be started as unprivileged user instead of root user
  - optional: works with read-only filesystem
- optional: downloads ngram language modules if configured (if they don't already exist)
- optional: downloads fasttext module (if it doesn't already exist)
- optional: allows to set log level

>⚠️ BREAKING CHANGE in version 6.6-0 ⚠️
>
>The default listen port inside the container has changed:
>- Previous versions: port 8010
>- New version (6.6-0): port 8081
>
>Either update your port mapping configuration to use the new port, or set the environment
>variable `LISTEN_PORT` to `8010` to retain old behavior.

## Setup

The following subsections show usage examples.<br/>
An example compose file can be downloaded from [here](https://raw.githubusercontent.com/meyayl/docker-languagetool/main/docker-compose.yml).

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
  --tmpfs /tmp \
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
      - /tmp
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

#### Docker CLI Usage

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
  --tmpfs /tmp \
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
    user: "783:783"
    read_only: true
    tmpfs:
      - /tmp
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

You need to install and use one of the add-ons from https://languagetool.org/services and configure it to use the self-hosted LanguageTool server `http://{ip-of-your-docker-host}:{published host port}/v2`. The self-hosted LanguageTool server does not come with its own UI or supports user authentication!

NOTE: Some add-ons require https connections, which is not (and will not be) supported by this image. You will need to put a reverse proxy in front of it to take care of the TLS termination.

## Capabilities

If the container is started as unprivileged user, the capabilities `CAP_CHOWN` `CAP_DAC_OVERRIDE`, `CAP_SETUID` and `CAP_SETGID`,  are not required, and can be omitted.
If the container is started as privileged user (default), and the environment variable `DISABLE_FILE_OWNER_FIX` is set to `true`, the capabilities `CAP_CHOWN` and `CAP_DAC_OVERRIDE` are not required and can be omitted.

## Ports

The self-hosted LanguageTool server in the container is listening on port `8081` by default.

It can be changed using the environment variable `LISTEN_PORT`.

## Volumes

| Required | Container Path | DESCRIPTION                                                                                                                                                                     |
|----------|----------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| no       | /ngrams        | Location to store the ngram language models. If container is started as unprivileged user, make sure the host path is owned by the user and/or group that starts the container. |
| no       | /fasttext      | Location to store the fasttext model. If container is started as unprivileged user, make sure the host path is owned by the user and/or group that starts the container.        |
| yes      | /tmp           | Location to store the created logback.xml and config.property. Preferably a tmpfs mount. |

Restrictions if only required volumes are used:
- privileged container: ngram language models and fasttext model will written into the container filesystem.
- read-only filesystem: neither ngram language models, nor fasttext model can be used.
- unprivileged container: neither ngram language models, nor fasttext model can be used.

## Parameters

The environment parameters are split into two halves, separated by an equal or colon, the left-hand side represents the variable name (use it as is), the right-hand side the value (change if necessary).

| ENV                       | DEFAULT                 | DESCRIPTION                                                                                                                                                                                                                     |
|---------------------------|-------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| download_ngrams_for_langs | none                    | Optional: Comma separated list of languages to download ngrams for. Skips download if the ngrams for that language already exist. Valid languages: `en`, `de`, `es`, `fr` and `nl`. Example value: `en,de`                      |
| langtool_languageModel    | /ngrams                 | Optional: The base path to the ngrams models.                                                                                                                                                                                   |
| langtool_fasttextBinary   | /usr/local/bin/fasttext | Optional: Path to the fasttext binary. Change only if you want to test your own compiled binary. Don't forget to map it into the container as volume.                                                                           |
| langtool_fasttextModel    | /fasttext/lid.176.bin   | Optional: The container path to the fasttext model binary. If the variable is set, the fasttext model will be downloaded if doesn't exist yet.                                                                                  |
| langtool_*                |                         | Optional: An arbitrary LanguageTool configuration, consisting of the prefix `langtool_` and the key name as written in the config file. Execute `docker run -ti --rm meyay/languagetool help` to see the list of config options. |
| JAVA_XMS                  | 256m                    | Optional: Minimum size of the Java heap space. Valid suffixes are `m` for megabytes and `g` for gigabytes.                                                                                                                      |
| JAVA_XMX                  | 1536m                   | Optional: Maximum size of the Java heap space. Valid suffixes are `m` for megabytes and `g` for gigabytes. Set a higher value if you experience OOM kills.                                                                      |
| JAVA_GC                   | ShenandoahGC            | Optional: Configure the garbage collector the JVM will use. Valid options are: `SerialGC`, `ParallelGC`, `ParNewGC`, `G1GC`, `ZGC`, `ShenandoahGC`                                                                              |
| JAVA_OPTS                 |                         | Optional: Set you own custom Java options for the JVM. This will render the other JAVA_* options useless.                                                                                                                       |
| LISTEN_PORT               | 8081                    | Optional: Set listen port of the self-hosted LanguageTool server inside the container.                                                                                                                                          |                                                                                                                                                                                                                       
| MAP_UID                   | 783                     | Optional: UID of the user inside the container that runs LanguageTool. If you encounter permission problems with your volumes, make sure to set the parameter to the UID of the host folder owner.                              |
| MAP_GID                   | 783                     | Optional: GID of the user inside the container that runs LanguageTool. If you encounter permission problems with your volumes, make sure to set the parameter to the GID of the host folder owner.                              |
| LOG_LEVEL                 | INFO                    | Optional: Set log level for LanguageTool. Valid options are: `TRACE`, `DEBUG`, `INFO`, `WARN`, `ERROR`.                                                                                                                         |
| DISABLE_FILE_OWNER_FIX    | false                   | Optional: Disables file ownership fix, if set to `true`. Will be used implicitly, if the container is started with an upriviliged user. The Valid options are: `true`, anything else is treated as `false`.      |
| DISABLE_FASTTEXT          | false                   | Optional: Disables fasttext, if set to `true`, neither the model is downloaded, nor fasttext enabled in LanguageTool.  The Valid options are: `true`, anything else is treated as `false`.                                      |
| DEBUG_ENTRYPOINT          |                         | Optional: Enables debug logs, if set to `true`. The Valid options are: `true`, anything else is treated as `false`.                                                                                                             |

## Fasttext support

Now that fasttext is available since Alpine 3.19, the image switched to using the Alpine package, instead of compiling the binaries from the sources. This hopefully fixes the compatibility issue users with older cpus experienced with my previous images, that were build on a amd64v3 architecture cpu, which compiled the `fasttext` binary with cpu optimizations older cpus do not support.

If the Alpine `fasttext` package does not work for you, you can build a custom image to compile the `fasttext` binary using cpu optimizations your cpu (as long as it's x86_64 based) actually understands:

```
git clone  https://github.com/meyayl/docker-languagetool.git
cd docker-languagetool
sudo docker build -t meyay/languagetool:latest -f Dockerfile.fasttext .
```

As alternative method, `sudo make docker_build` can be used to build your custom image.

Once the image is build, you can `docker compose up -d` like you would do with the images hosted on Docker Hub.

>NOTE1: From now on the fastText sources are patched to work with gcc13.

>NOTE2: Synology users can find a git package in the [SynoCommunity](https://synocommunity.com) repository.

## Changelog

| Date                           | Tag       | Change                                                                                                                                                                                                                                                                                       |
|--------------------------------|-----------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 2025-04-20                     | 6.6-1    | - Fix read-only mode for Synology DSM6.2 with aufs<br/> - Replace cve affected logback-core and logback-classic with package version 1.5.18                                                                                                                                                  |
| 2025-04-19                     | 6.6-0     | - Breaking: Changed LISTEN_PORT from 8010 to 8081<br/> - Extended sanity checks and log output in entrypoint script<br/> - Update Java to 21.0.7+6                                                                                                                                           |
| 2025-02-16                     | 6.5-2     | - Update base image to Alpine 3.21.3<br/> - Update Java to 21.0.6+7                                                                                                                                                                                                                          |
| 2024-10-30                     | 6.5-1     | - Massive refactoring of Entrypoint script<br/> - Update Java to 21.0.5+11                                                                                                                                                                                                                   |
| 2024-09-29                     | 6.5-0     | - Update to LaguageTool 6.5                                                                                                                                                                                                                                                                  |
| 2024-09-14                     | 6.4-4     | - Update base image to Alpine 3.20.3                                                                                                                                                                                                                                                         | 
| 2024-07-31                     | 6.4-3     | - Update base image to Alpine 3.20.2<br/> - Update Java to 21.0.4+7                                                                                                                                                                                                                          |
| 2024-07-05                     | 6.4-2     | - Update base image to Alpine 3.20.1<br/> - Update Java to 21.0.3+9                                                                                                                                                                                                                          |
| 2024-05-27                     | 6.4-1     | - Update base image to Alpine 3.20.0                                                                                                                                                                                                                                                         |
| 2024-04-02                     | 6.4-0     | - Update to LanguageTool 6.4<br/> - Modified entrypoint script, to require 7x5 permissions instead of 7x7 for ngrams and fasttext volumes anymore.                                                                                                                                           | 
| 2024-03-26                     | 6.3a-5    | - Update Java to 21.0.2+13<br/> - Add capability CAP_CHOWN to README.md and compose file.                                                                                                                                                                                                    | 
| 2024-02-26                     | 6.3a-4    | - Fix entrypoint script bug that affected new users when downloading the ngram models.                                                                                                                                                                                                       |
| 2024-02-17                     | 6.3a-3    | - Update base image to Alpine 3.19.1<br/> - Migrate from compiling fasttext to using the Alpine fasttext package.                                                                                                                                                                            |
| 2024-02-17                     | 6.3a-2    | - Modify Dockerfile to create the LanguageTool user without home directory<br/> - Modify entrypoint script to modify uid:gid of languagetool user and group if actually changed.                                                                                                             |
| 2024-02-12                     | 6.3a-1    | - Update base image to Alpine 3.18.6<br/> - Update Java to 17.0.10+7                                                                                                                                                                                                                         |
| 2023-12-20                     | 6.3a-0    | - Update to LanguageTool 6.3a                                                                                                                                                                                                                                                                |
| 2023-12-03                     | 6.3-1     | - Update base image to Alpine 3.18.5<br/> - Update Java to 17.0.9+9                                                                                                                                                                                                                          |
| 2023-10-10                     | 6.3-0     | - Update to LanguageTool 6.3<br/> - Update base image to Alpine 3.18.4<br/> - Update Java to 17.0.8.1+1                                                                                                                                                                                      |
| 2023-08-10                     | 6.2-1     | - Update base image to Alpine 3.18.3<br/> - Update Java to 17.0.8+7                                                                                                                                                                                                                          |
| 2023-07-09                     | 6.2-0     | - Update to LanguageTool 6.2                                                                                                                                                                                                                                                                 |
| 2023-06-30                     | 6.1-4     | - Update base image to Alpine 3.18.2                                                                                                                                                                                                                                                         |
| 2023-05-19                     | 6.1-3     | - Update base image to Alpine 3.18.0<br/> - Update Java to 17.0.7+7                                                                                                                                                                                                                          |
| 2023-04-01                     | 6.1-2     | - Update base image to Alpine 3.17.3.                                                                                                                                                                                                                                                        |
| 2023-03-28                     | 6.1-1     | - Add logic to set log level                                                                                                                                                                                                                                                                 |
| 2023-03-28                     | 6.1-0     | - Upgrade to LanguageTool 6.1                                                                                                                                                                                                                                                                |  
| 2023-02-23                     | 6.0-5     | - Update base image to Alpine 3.17.2.                                                                                                                                                                                                                                                        |
| 2023-01-23                     | 6.0-4     | - Update Java to Eclipse Temurin 17.0.6+10.                                                                                                                                                                                                                                                  |
| 2023-01-15                     | 6.0-3     | - Update base image to Alpine 3.17.1.                                                                                                                                                                                                                                                        |
| 2023-01-01                     | 6.0-2     | - Add alpine package `gcompat` to satisfy `ld-linux-x86-64.so.2` dependency.<br/>(this fixes the issue of the 6.0-1 image)                                                                                                                                                                   |
| ~~2022-12-29~~<br/>2023-01-01  | ~~6.0-1~~ | ~~- Upgrade to languagetool 6.0~~<br/> - Removed tag due to ClassPath exception.                                                                                                                                                                                                             |
| 2022-12-07                     | 5.9-7     | - Fix health check command                                                                                                                                                                                                                                                                   |
| 2022-12-04                     | 5.9-6     | - Add `help` command to display LanguageTool configuration items to be used with `languagetool_*`                                                                                                                                                                                            |
| 2022-12-04                     | 5.9-5     | - Switch to stripped down Eclipse Temurin 17 JRE <br/> - Remove JVM argument `-XX:+UseStringDeduplication` except for G1GC <br/> - Add `tini` to suppress exit code 143 <br/> - Removed `curl` and switch to `wget` <br/> - Print version info about Alpine and Eclipse Temurin during start |
| 2022-11-29                     | 5.9-4     | - Update base image to Alpine 3.17.0                                                                                                                                                                                                                                                         |
| 2022-11-24                     | 5.9-3     | - Add support to configure garbage collector <br/> - Add JVM argument `-XX:+UseStringDeduplication` <br/> - Add support to pass custom JAVA_OPTS <br/> - Change Java_Xm? variables to JAVA_XM?                                                                                               |
| 2022-11-12                     | 5.9-2     | - Update base image to Alpine 3.16.3                                                                                                                                                                                                                                                         |
| 2022-09-28                     | 5.9-1     | - Update LanguageTool to 5.9                                                                                                                                                                                                                                                                 |
| 2022-09-10                     | 5.8-2     | - Add user mapping support                                                                                                                                                                                                                                                                   |
| 2022-09-10                     | 5.8-1     | - Initial release with Alpine 3.16.2, LanguageTool 5.8                                                                                                                                                                                                                                       |
