#!/bin/bash
set -eo pipefail

# enabled debug for entrypoint script
is_debug() {
  [[ -n "${DEBUG_ENTRYPOINT}" ]] && [[ "${DEBUG_ENTRYPOINT}" == "true" ]]
}
export -f is_debug

is_debug && set -x

print_lt_help() {
  # Print help information for LanguageTool
  if [[ $# -ne 0 ]] && [[ "${1}" == "help" ]]; then
    local print_line=false
    while IFS= read -r line; do
      if grep -q '\-\-config FILE' <<< "${line}"; then
        print_line=true
      fi
      if grep -q '\-\-port' <<< "${line}"; then
        print_line=false
      fi
      [[ "${print_line}" == "true" ]] && echo "${line}"
    done <<< "$(java -cp languagetool-server.jar org.languagetool.server.HTTPServer --help)"
    exit 0
  fi
}

is_root() {
  [[ $(id -u) -eq 0 ]]
}

is_ro_mount(){
  [[ "$(awk '/^[[:alnum:]]* \/ /{ if ($1 != "rootfs") { split($4,mount_opts,","); for (i = 1; i <= length(mount_opts); i++){if (mount_opts[i] == "ro" || mount_opts[i] == "rw" ){print mount_opts[i];}}}}' /proc/mounts)" == "ro" ]]
}

download_and_extract_ngram_language_model(){
  is_debug && set -x

  local _LANG
  _LANG="${1}"
  local _BASE_URL
  _BASE_URL="https://languagetool.org/download/ngram-data"

  # mapping for ngram language models
  declare -A ngrams_filesnames
  ngrams_filesnames[en]=ngrams-en-20150817.zip
  ngrams_filesnames[de]=ngrams-de-20150819.zip
  ngrams_filesnames[es]=ngrams-es-20150915.zip
  ngrams_filesnames[fr]=ngrams-fr-20150913.zip
  ngrams_filesnames[nl]=ngrams-nl-20181229.zip

  if [[ ! -d "${langtool_languageModel}/${_LANG}" ]]; then
    if [[ ! -e "${langtool_languageModel}/ngrams-${_LANG}.zip" ]] || ! unzip -t "${langtool_languageModel}/ngrams-${_LANG}.zip" > /dev/null 2>&1; then
      echo -e "${INFO}: Downloading \"${_LANG}\" ngrams."
      wget -O "${langtool_languageModel}/ngrams-${_LANG}.zip" "${_BASE_URL}/${ngrams_filesnames[${_LANG}]}" || {
        echo -e "${ERROR}: Failed to download ngrams for language ${lang}."
        rm -f "${langtool_languageModel}/ngrams-${_LANG}.zip"
        exit 1
      }
    fi
    if [[ -e "${langtool_languageModel}/ngrams-${_LANG}.zip" ]]; then
      echo -e "${INFO}: Extracting \"${_LANG}\" ngram language model."
      unzip "${langtool_languageModel}/ngrams-${_LANG}.zip" -d "${langtool_languageModel}" || {
        echo -e "${ERROR}: Failed to extract ngrams for language ${lang}."
        rm -f "${langtool_languageModel}/ngrams-${_LANG}.zip"
        exit 1
      }
      rm -f "${langtool_languageModel}/ngrams-${_LANG}.zip"
    fi
  else
    echo -e "${INFO}: Skipping download of ngram model for language ${_LANG}: already exists."
  fi
}
# Export the function so it's available to the new shell
export -f download_and_extract_ngram_language_model

handle_ngram_language_models(){
  is_debug && set -x

  # do not download ngram models
  if [[ -z "${download_ngrams_for_langs}" ]] || [[ "${download_ngrams_for_langs}" == "none" ]] ; then
   echo -e "${WARN}: \"download_ngrams_for_langs\" not provided, no ngrams will be downloaded."
   return
  fi

  # no download folder provided
  if [[ -z "${langtool_languageModel}" ]]; then
     echo -e "${ERROR}: No base path for ngram language models provided. Language Tool will not download ngram models. It will only use existing ngram models."
     return
  fi

  dir_uid=$( stat -c '%u' "${langtool_languageModel}" 2> /dev/null)
  actual_uid=$(id -u)
  dir_gid=$( stat -c '%g' "${langtool_languageModel}" 2> /dev/null)
  actual_gid=$(id -g)

  # download folder not owned by user or group id
  can_write=true
  if [[ ! -x "${langtool_languageModel}" ]] && [[ ! -w "${langtool_languageModel}" ]];then
    echo -e "${ERROR}: Directory \"${langtool_languageModel}\" does not allow the user or group to enter it or write into it."
    can_write=false
  fi

  if [[ "${dir_uid}" != "${actual_uid}" ]] && [[ "${dir_gid}" != "${actual_gid}" ]] ;then
    echo -e "${ERROR}: Directory \"${langtool_languageModel}\" is owned by ${dir_uid}:${dir_gid}, but should be owned by uid ${actual_uid} and/or gid ${actual_gid}."
    can_write=false
  fi
  if [[ "${can_write}" == "false" ]]; then
     exit 1
  fi

  echo -e "${INFO}: Directory ${langtool_languageModel} is owned by ${dir_uid}:${dir_gid}"
  IFS=',' read -ra langs <<< "${download_ngrams_for_langs}"
  for lang in "${langs[@]}"; do
    case "${lang}" in
      en|de|es|fr|nl)
        download_and_extract_ngram_language_model "${lang}"
        ;;
      none)
        ;;
      *)
        echo -e "${ERROR}: Unknown ngrams language. Supported languages are \"en\", \"de\", \"es\", \"fr\" and \"nl\"."
        exit 1
    esac
  done
}
# Export the function so it's available to the new shell
export -f handle_ngram_language_models

download_fasttext_model(){
  is_debug && set -x

  if [[ -z "${langtool_fasttextModel}" ]] || [[ "${DISABLE_FASTTEXT}" == "true" ]]; then
      echo -e "${INFO}: \"langtool_fasttextModel\" not specified or \"DISABLE_FASTTEXT\" is set to \"true\". Skipping download of fasttext model."
      unset langtool_fasttextModel
      return
  fi

  # download folder not owned by user or group id
  dir_uid=$(stat -c '%u' "${langtool_fasttextModel%/*}" 2> /dev/null)
  actual_uid=$(id -u)
  dir_gid=$(stat -c '%g' "${langtool_fasttextModel%/*}" 2> /dev/null)
  actual_gid=$(id -g)

  can_write=true
  if [[ ! -x "${langtool_fasttextModel%/*}" ]] && [[ ! -w "${langtool_fasttextModel%/*}" ]];then
    echo -e "${ERROR}: Directory \"${langtool_fasttextModel%/*}\" does not allow the user or group to enter it or write into it."
    can_write=false
  fi

  if [[ "${dir_uid}" != "${actual_uid}" ]] && [[ "${dir_gid}" != "${actual_gid}" ]] ;then
    echo -e "${ERROR}: Directory \"${langtool_fasttextModel%/*}\" is owned by ${dir_uid}:${dir_gid}, but should be owned by uid ${actual_uid} and/or gid ${actual_gid}."
    can_write=false
  fi
  if [[ "${can_write}" == "false" ]]; then
     exit 1
  fi

  echo -e "${INFO}: Directory ${langtool_fasttextModel%/*} is owned by ${dir_uid}:${dir_gid}."
  if [[ ! -e "${langtool_fasttextModel}" ]]; then
    echo -e "${INFO}: Downloading fasttext model."
    wget  -O "${langtool_fasttextModel}" "https://dl.fbaipublicfiles.com/fasttext/supervised-models/lid.176.bin"
  else
    echo -e "${INFO}: Skipping download of fasttext model: already exists."
  fi
}
# Export the function so it's available to the new shell
export -f download_fasttext_model

fix_dir_owner(){
  local _PATH
  _PATH="${1}"
  if [[ -x "${_PATH}" ]]; then
    find "${_PATH}"  ! \( -user  "languagetool" -group "languagetool" \) -exec chown "languagetool:languagetool" {} \;
  else
    cat << EOF
$(echo -e "${WARN}"): permissions on "${_PATH}" do not allow to fix ownership.
      If this is intentional, please set environment variable DISABLE_PERMISSION_FIX to true to disable this feature.
EOF
  fi
}

fix_ownership(){
  if [[ -n "${langtool_languageModel}" ]]; then
    echo -e "${INFO}: Fixing ownership for ngrams base folder if necessary."
    fix_dir_owner "${langtool_languageModel}"
  fi
  if [[ -n "${langtool_fasttextModel}" ]]; then
    echo -e "${INFO}: Fixing ownership for fasttext model file if necessary."
    fix_dir_owner "$(dirname "${langtool_fasttextModel}")"
  fi
}

create_config(){
  local _config_file="${1}"

  echo -e "${INFO}: Creating new LanguageTool config file."
  if [[ -e "${_config_file}" ]]; then
    rm "${_config_file}"
    touch "${_config_file}"
  fi

  for varname in ${!langtool_*}; do
    config_injected=true
    echo -e "${varname#'langtool_'}=${!varname}" >> "${_config_file}"
  done
}

user_map(){
  if [[ -n "${MAP_UID}" ]]; then
    CURRENT_UID="$(id languagetool -u)"
    if [[ "${MAP_UID}" != "${CURRENT_UID}" ]]; then
      echo -e "${INFO}: Setting uid for user \"languagetool\" to ${MAP_UID}."
      usermod -u "${MAP_UID}" languagetool
    fi
  fi
  if [[ -n "${MAP_GID}" ]]; then
    CURRENT_GID="$(id languagetool -g)"
    if [[ "${MAP_GID}" != "${CURRENT_GID}" ]]; then
      EXISTING_GROUP=$(getent group ${MAP_GID} | cut -d: -f1) || true
      if [[ -n "${EXISTING_GROUP}" ]]; then
        echo -e "${INFO}: Group \"${EXISTING_GROUP}\" already exists with gid ${MAP_GID}."
        echo -e "${INFO}: Setting primary gid for user \"languagetool\" from ${CURRENT_GID} to ${MAP_GID}."
        usermod -g "${MAP_GID}" languagetool
      else
        echo -e "${INFO}: Changing gid of group \"languagetool\" to gid ${MAP_GID}."
        groupmod -g "${MAP_GID}" languagetool
      fi
    fi
  fi
}

print_info(){
  echo -e "${INFO}: Version Information:"
  local _ALPINE_VERSION
  _ALPINE_VERSION=$(grep "VERSION_ID=" /etc/os-release | cut -d'=' -f2)
  echo -e "Alpine Linux v${_ALPINE_VERSION}" | indent
  java --version | indent
}

indent() { sed 's/^/  /'; }

is_cap_enabled() {
    local _CHECK_CAP="${1}"

    caps=$(awk '/^CapPrm:/ {print $2}' /proc/self/status)

    # Convert hex to decimal
    caps=$((16#$caps))

    case "${_CHECK_CAP}" in
      CAP_CHOWN)  [[ $((caps & 1)) -ne 0 ]]
                  ;;
      CAP_DAC_OVERRIDE) [[ $((caps & 2)) -ne 0 ]]
                  ;;
      CAP_DAC_READ_SEARCH) [[ $((caps & 4)) -ne 0 ]]
                  ;;
      CAP_FOWNER) [[ $((caps & 8)) -ne 0 ]]
                  ;;
      CAP_SETUID) [[ $((caps & 64)) -ne 0 ]]
                  ;;
      CAP_SETGID) [[ $((caps & 128)) -ne 0 ]]
                  ;;
    esac
}

print_capability_status() {
    if [ "$1" = true ]; then
        echo -e "${GREEN}yes${NC}"
    else
        echo -e "${RED}no${NC}"
    fi
}

# main
print_lt_help "$@"

# Define color codes. Note: export is to required to work with "su -m"
export GREEN='\033[0;32m'
export RED='\033[0;31m'
export ORANGE='\033[0;33m'
export NC='\033[0m' # No Color

# Define colored output. Note: export is to required to work with "su -m"
export INFO="${GREEN}INFO${NC}"
export WARN="${ORANGE}WARN${NC}"
export ERROR="${RED}ERROR${NC}"

if is_root; then

  EXPECTED_IDS="${MAP_UID}:${MAP_GID}"
  OWNER_FIX=true
  USER_MAPPING=true

  echo -e "${INFO}: Container started as root user."
  echo -e "${INFO}: Available capabilities:"
  echo -e "  CAP_CHOWN         Can change owner of files and directories: $(is_cap_enabled CAP_CHOWN && print_capability_status true || print_capability_status false)"
  echo -e "  CAP_DAC_OVERRIDE  Can bypass file permission checks when changing owner: $(is_cap_enabled CAP_DAC_OVERRIDE  && print_capability_status true || print_capability_status false)"
  echo -e "  CAP_SETUID        Can execute languagetool with arbitrary uid: $(is_cap_enabled CAP_SETUID && print_capability_status true || print_capability_status false)"
  echo -e "  CAP_SETGUID       Can execute languagetool with arbitrary gid: $(is_cap_enabled CAP_SETGID && print_capability_status true || print_capability_status false)"

  if is_ro_mount "/"; then
     echo -e "${INFO}: Container started with readonly filesystem."
     USE_NSS_WRAPPER=false
     if [[ -n "${MAP_UID}" ]]; then
       CURRENT_UID="$(id languagetool -u)"
        if [[ "${MAP_UID}" != "${CURRENT_UID}" ]]; then
          USE_NSS_WRAPPER=true
        fi
     fi
    if [[ -n "${MAP_GID}" ]]; then
      CURRENT_GID="$(id languagetool -g)"
      if [[ "${MAP_GID}" != "${CURRENT_GID}" ]]; then
          USE_NSS_WRAPPER=true
      fi
    fi
    if [[ "${USE_NSS_WRAPPER}" == "true" ]]; then
   		export LD_PRELOAD='/usr/lib/libnss_wrapper.so'
   		export NSS_WRAPPER_PASSWD="$(mktemp)"
   		export NSS_WRAPPER_GROUP="$(mktemp)"

      echo "languagetool:x:${MAP_UID}:${MAP_GID}:languagetool gecos:/home/languagetool:/sbin/nologin" > "${NSS_WRAPPER_PASSWD}"
   		echo "languagetool:x:${MAP_GID}:" > "${NSS_WRAPPER_GROUP}"

   		chmod +r "${NSS_WRAPPER_PASSWD}"
   		chmod +r "${NSS_WRAPPER_GROUP}"

   		echo -e "${INFO}: using nss_wrapper to set uid for user \"languagetool\" to ${MAP_UID} and gid for group \"languagetool\" to ${MAP_GID}."
    fi
  fi
  if [[ "${DISABLE_FILE_OWNER_FIX}" == "true" ]]; then
    OWNER_FIX=false
    echo -e "${INFO}: Container started with DISABLE_FILE_OWNER_FIX=${DISABLE_FILE_OWNER_FIX}. This disables the ownership fix of directories."
  fi
  if [[ "${USER_MAPPING}" == "true" ]] && [[ "${USE_NSS_WRAPPER}" != "true" ]]; then
    user_map
  fi
  if [[ "${OWNER_FIX}" == "true" ]] && is_cap_enabled "CAP_CHOWN" && is_cap_enabled "CAP_DAC_OVERRIDE"; then
    fix_ownership
  else
    echo -e "${WARN}: Container started without sufficient capabilities to fix ownership of directories."
    echo -e "  Make sure the volumes have have the correct permissions and are owned by ${EXPECTED_IDS}."
  fi

else
  EXPECTED_IDS="$(id -u):$(id -g)"
  echo -e "${INFO}: Container started as unprivileged UID:GID ${EXPECTED_IDS}. Skipping User mapping."
  echo -e "      Make sure the volumes have have the correct permissions and are owned by ${EXPECTED_IDS}."
fi

# download ngram models and fasttext model as MAP_UID:MAP_GID user
if [[ "${USER_MAPPING}" == "true" ]]; then
    su -m -s /bin/bash languagetool -c 'handle_ngram_language_models'
    su -m -s /bin/bash languagetool -c 'download_fasttext_model'
else
    handle_ngram_language_models
    download_fasttext_model
fi

if [[ "${CONTAINER_MODE}" == "download-only" ]]; then
    echo -e "${INFO}: Variable \"CONTAINER_MODE\" set to \"download-only\". Stopping the container."
    exit 0
fi

if [[ "${DISABLE_FASTTEXT}" != "true" ]]; then
  if [[ -z "${langtool_fasttextBinary}" ]]; then
    echo -e "${INFO}: Variable \"langtool_fasttextBinary\" not set. Fasttext can not be used."
    DISABLE_FASTTEXT=true
  else
    if [[ ! -e "${langtool_fasttextBinary}" ]]; then
      echo -e "${WARN}: Fasttext binary not found at \"${langtool_fasttextBinary}\". Fasttext can not be used."
      DISABLE_FASTTEXT=true
    else
      if [[ ! -x "${langtool_fasttextBinary}" ]]; then
        echo -e "${WARN}: Fasttext binary has not execution permission \"${langtool_fasttextBinary}\". Fasttext can not be used."
        DISABLE_FASTTEXT=true
      fi
    fi
  fi
  if [[ -z "${langtool_fasttextModel}" ]]; then
    echo -e "${INFO}: Variable \"langtool_fasttextModel\" not set. Fasttext can not be used."
    DISABLE_FASTTEXT=true
  else
    if [[ ! -e "${langtool_fasttextModel}" ]]; then
      echo -e "${WARN}: Fasttext model not found at \"${langtool_fasttextModel}\". Fasttext can not be used."
      DISABLE_FASTTEXT=true
    fi
  fi
fi

if [[ "${DISABLE_FASTTEXT}" == "true" ]] ; then
  echo -e "${WARN}: Fasttext support is disabled."
  unset langtool_fasttextModel
  unset langtool_fasttextBinary
fi

# create config
CONFIG_FILE=/tmp/config.properties
create_config "${CONFIG_FILE}"

print_info

# show current languagetool config
if [[ "$config_injected" = true ]]; then
  echo -e "${INFO}: Using following LanguageTool configuration:"
  indent < "${CONFIG_FILE}"
fi

# set default JAVA_OPTS with default memory limits and garbage collector
if [[ -z "${JAVA_OPTS}" ]]; then
  JAVA_GC="${JAVA_GC:-ShenandoahGC}"
  for gc in ShenandoahGC SerialGC ParallelGC ParNewGC G1GC ZGC; do
    if [[ "${JAVA_GC}" == "${gc}" ]]; then
      JAVA_GC_OPT="-XX:+Use${JAVA_GC}"
      if [[ "${JAVA_GC}" == "G1GC" ]]; then
        JAVA_GC_OPT+=" -XX:+UseStringDeduplication"
      fi;
      break
    fi
  done
  JAVA_OPTS="-Xms${JAVA_XMS:-256m} -Xmx${JAVA_XMX:-1536m} ${JAVA_GC_OPT}"
  echo -e "${INFO}: Using JAVA_OPTS=${JAVA_OPTS}"
else
  echo -e "JAVA_OPTS environment variables detected."
  echo -e "${INFO}: Using JAVA_OPTS=${JAVA_OPTS}"
fi

read -ra FINAL_JAVA_OPTS <<< "${JAVA_OPTS}"

#setloglevel
cp "${LOGBACK_CONFIG}" /tmp/logback.xml
xml edit --inplace --update "/configuration/logger[@name='org.languagetool']/@level" --value "${LOG_LEVEL}" /tmp/logback.xml

if [[ $# -gt 0 ]] && [[ "$1" != "help" ]]; then
  unset RED GREEN ORANGE NC INFO WARN ERROR
  if is_root; then
    su-exec "${MAP_UID}:${MAP_GID}" "$@"
  else
    exec "$@"
  fi
  exit 0
fi

# start languagetool
echo -e "${INFO}: StartingLanguage Tool Standalone Server (or custom command)"
echo "--------------------------------------------------------------------"

# cleanup variables
unset RED GREEN ORANGE NC INFO WARN ERROR

if is_root; then
  EXECUTE_ARGS="su-exec ${MAP_UID}:${MAP_GID}"
else
  EXECUTE_ARGS="exec"
fi

read -ra FINAL_EXECUTE_ARGS <<< "${EXECUTE_ARGS}"

"${FINAL_EXECUTE_ARGS[@]}" \
    java "${FINAL_JAVA_OPTS[@]}" -Djna.tmpdir="/tmp" -Dlogback.configurationFile="/tmp/logback.xml" -cp languagetool-server.jar org.languagetool.server.HTTPServer \
      --port "${LISTEN_PORT:-8081}" \
      --public \
      --allow-origin "*" \
      --config /tmp/config.properties
