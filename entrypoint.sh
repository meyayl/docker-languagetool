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
      echo "INFO: Downloading \"${_LANG}\" ngrams."
      wget -O "${langtool_languageModel}/ngrams-${_LANG}.zip" "${_BASE_URL}/${ngrams_filesnames[${_LANG}]}" || {
        echo "ERROR: Failed to download ngrams for language ${lang}."
        exit 1
      }
    fi
    if [[ -e "${langtool_languageModel}/ngrams-${_LANG}.zip" ]]; then
      echo "INFO: Extracting \"${_LANG}\" ngram language model."
      unzip "${langtool_languageModel}/ngrams-${_LANG}.zip" -d "${langtool_languageModel}" || {
        echo "ERROR: Failed to extract ngrams for language ${lang}."
        rm "${langtool_languageModel}/ngrams-${_LANG}.zip"
        exit 1
      }
      rm "${langtool_languageModel}/ngrams-${_LANG}.zip"
    fi
  else
    echo "INFO: Skipping download of ngram model for language ${_LANG}: already exists."
  fi
}
# Export the function so it's available to the new shell
export -f download_and_extract_ngram_language_model

handle_ngram_language_models(){
  is_debug && set -x

  if [[ -z "${langtool_languageModel}" ]]; then
     echo "ERROR: No base path for ngram language models provided. Language Tool will not download or use any ngram models."
  fi
  dir_uid=$( stat -c '%u' "${langtool_languageModel}")
  actual_uid=$(id -u)
  if [[ "${dir_uid}" == "${actual_uid}" ]];then
     echo "INFO: directory ${langtool_languageModel} is owned by ${dir_uid}."
  else
     echo "ERROR: directory ${langtool_languageModel} is owned by ${dir_uid}, but should be owned by ${actual_uid}."
     exit 1
  fi
  if [[ -z "${download_ngrams_for_langs}" ]]; then
      echo "WARNING: download_ngrams_for_langs not provided, no ngrams will be downloaded."
  fi
  IFS=',' read -ra langs <<< "${download_ngrams_for_langs}"
  for lang in "${langs[@]}"; do
    case "${lang}" in
      en|de|es|fr|nl)
        download_and_extract_ngram_language_model "${lang}"
        ;;
      none)
        ;;
      *)
        echo "ERROR: Unknown ngrams language. Supported languages are \"en\", \"de\", \"es\", \"fr\" and \"nl\"."
        exit 1
    esac
  done
}
# Export the function so it's available to the new shell
export -f handle_ngram_language_models

download_fasttext_model(){
  is_debug && set -x

  if [[ -z "${langtool_fasttextModel}" ]] || [[ "${DISABLE_FASTTEXT}" == "true" ]]; then
      echo "INFO: \"langtool_fasttextModel\" not specified or \"DISABLE_FASTTEXT\" is set to \"true\". Skipping download of fasttext model."
      unset langtool_fasttextModel
      return
  fi

  if [[ ! -e "${langtool_fasttextModel}" ]]; then
    dir_uid=$( stat -c '%u' "${langtool_fasttextModel%/*}")
    actual_uid=$(id -u)
    if [[ "${dir_uid}" == "${actual_uid}" ]];then
       echo "Info: directory ${langtool_fasttextModel%/*} is owned by ${dir_uid}."
    else
       echo "ERROR: directory ${langtool_fasttextModel%/*} is owned by ${dir_uid}, but should be owned by ${actual_uid}."
       exit 1
    fi
    echo "INFO: Downloading fasttext model."
    wget  -O "${langtool_fasttextModel}" "https://dl.fbaipublicfiles.com/fasttext/supervised-models/lid.176.bin"
  else
    echo "INFO: Skipping download of fasttext model: already exists."
    file_uid=$( stat -c '%u' "${langtool_fasttextModel}")
    actual_uid=$(id -u)
    if [[ "${file_uid}" == "${actual_uid}" ]];then
       echo "INFO: file ${langtool_fasttextModel} is owned by userid ${file_uid}."
    else
       echo "ERROR: file ${langtool_fasttextModel} is owned by ${file_uid}, but should be owned by ${actual_uid}."
       exit 1
    fi
  fi
}
# Export the function so it's available to the new shell
export -f download_fasttext_model

fix_dir_owner(){
  local _PATH
  _PATH="${1}"
  if [ -x "${_PATH}" ] ; then
    find "${_PATH}"  ! \( -user  languagetool -group languagetool \) -exec chown languagetool:languagetool {} \;
  else
    cat << EOF
WARN: permissions of directory "${_PATH}" prevents operation.
  If this is intentional, please set environment variable DISABLE_PERMISSION_FIX to true to disable this feature.
  If not run "sudo chmod o+x,o+r -R {path}" (replace {path} with your real host path!)
EOF
  fi
}

fix_ownership(){
  if [[ -n "${langtool_languageModel}" ]]; then
    echo "INFO: Fixing ownership for ngrams base folder if necessary."
    fix_dir_owner "${langtool_languageModel}"
  fi
  if [[ -n "${langtool_fasttextModel}" ]]; then
    echo "INFO: Fixing ownership for fasttext model file if necessary."
    fix_dir_owner "$(dirname "${langtool_fasttextModel}")"
  fi
}

create_config(){
  local _config_file="${1}"

  echo "INFO: Creating new LanguageTool config file."
  if [[ -e "${_config_file}" ]]; then
    rm "${_config_file}"
    touch "${_config_file}"
  fi

  for varname in ${!langtool_*}; do
    config_injected=true
    echo "${varname#'langtool_'}=${!varname}" >> "${_config_file}"
  done
}

user_map(){
  if [[ -n "${MAP_UID}" ]]; then
    CURRENT_UID="$(id languagetool -u)"
    if [[ "${MAP_UID}" != "${CURRENT_UID}" ]]; then
      echo "INFO: Setting uid for user \"languagetool\" to ${MAP_UID}."
      usermod -u "${MAP_UID}" languagetool
    fi
  fi
  if [[ -n "${MAP_GID}" ]]; then
    CURRENT_GID="$(id languagetool -g)"
    if [[ "${MAP_GID}" != "${CURRENT_GID}" ]]; then
      echo "INFO: Setting gid for group \"languagetool\" to ${MAP_GID}."
      groupmod -g "${MAP_GID}" languagetool
    fi
  fi
}

print_info(){
  echo "INFO: Version Information:"
  local _ALPINE_VERSION
  _ALPINE_VERSION=$(grep "VERSION_ID=" /etc/os-release | cut -d'=' -f2)
  echo "Alpine Linux v${_ALPINE_VERSION}" | indent
  java --version | indent
}

indent() { sed 's/^/  /'; }

# main
print_lt_help "$@"

# actions that require root user and permission fixes
if is_root  && [[ "${DISABLE_PERMISSION_FIX}" != "true" ]]; then
  user_map
  fix_ownership
else
  if is_root; then
    EXPECTED_IDS="${MAP_UID}:${MAP_GID}"
  else
    EXPECTED_IDS="$(id -u):$(id -g)"
  fi
  cat << EOF
INFO: Container started as UID:GID $(id -u):$(id -g) with DISABLE_PERMISSION_FIX=${DISABLE_PERMISSION_FIX}.

- Usermapping is not available. Make sure your volumes are owned by that user!
- Ownership of directory can not be fixed. Makes sure your volume have the correct permissions set and are owned by ${EXPECTED_IDS}.

EOF
fi

# download ngram models and fasttext model as user
if is_root; then
  su -s /bin/bash languagetool -c 'handle_ngram_language_models'
  su -s /bin/bash languagetool -c 'download_fasttext_model'
else
  DISABLE_PERMISSION_FIX=false
  handle_ngram_language_models
  download_fasttext_model
fi

# create config
CONFIG_FILE=/tmp/config.properties
create_config "${CONFIG_FILE}"

print_info

# show current languagetool config
if [[ "$config_injected" = true ]]; then
  echo 'INFO: Using following LanguageTool configuration:'
  indent < "${CONFIG_FILE}"
fi

# set default JAVA_OPTS with default memory limits and garbage collector
if [[ -z "${JAVA_OPTS}" ]]; then
  JAVA_GC="${JAVA_GC:-ShenandoahGC}"
  for gc in SerialGC ParallelGC ParNewGC G1GC ZGC ShenandoahGC; do
    if [[ "${JAVA_GC}" == "${gc}" ]]; then
      JAVA_GC_OPT="-XX:+Use${JAVA_GC}"
      if [[ "${JAVA_GC}" == "G1GC" ]]; then
        JAVA_GC_OPT+=" -XX:+UseStringDeduplication"
      fi;
      break
    fi
  done
  JAVA_OPTS="-Xms${JAVA_XMS:-256m} -Xmx${JAVA_XMX:-1536m} ${JAVA_GC_OPT}"
  echo "INFO: Using JAVA_OPTS=${JAVA_OPTS}"
else
  echo "JAVA_OPTS environment variables detected."
  echo "INFO: Using JAVA_OPTS=${JAVA_OPTS}"
fi

read -ra FINAL_JAVA_OPTS <<< "${JAVA_OPTS}"

#setloglevel
cp "${LOGBACK_CONFIG}" /tmp/logback.xml
xml edit --inplace --update "/configuration/logger[@name='org.languagetool']/@level" --value "${LOG_LEVEL}" /tmp/logback.xml

if [[ $# -gt 0 ]] && [[ "$1" != "help" ]]; then
  if is_root; then
    exec su-exec languagetool:languagetool "$@"
  else
    exec "$@"
  fi
  exit 0
fi

# start languagetool
echo "INFO: StartingLanguage Tool Standalone Server (or custom command)"
if is_root; then
  EXECUTE_ARGS="su-exec languagetool:languagetool"
else
  EXECUTE_ARGS=""
fi

read -ra FINAL_EXECUTE_ARGS <<< "${EXECUTE_ARGS}"

exec "${FINAL_EXECUTE_ARGS[@]}" \
    java "${FINAL_JAVA_OPTS[@]}" -Dlogback.configurationFile="/tmp/logback.xml" -cp languagetool-server.jar org.languagetool.server.HTTPServer \
      --port "${LISTEPORT:-8010}" \
      --public \
      --allow-origin "*" \
      --config /tmp/config.properties
