#!/bin/bash
set -eo pipefail

# enabled debug for entrypoint script
if [ ! -z "${DEBUG_ENTRYPOINT}" ] && [ "${DEBUG_ENTRYPOINT}" == "true" ]; then
  set -x
fi

fix_dir_owner(){
  local _PATH="${1}"
  find "${_PATH}"  ! \( -user  languagetool -group languagetool \) -exec chown languagetool:languagetool {} \;
}

# download ngrams

declare -A ngrams_filesnames
ngrams_filesnames[en]=ngrams-en-20150817.zip
ngrams_filesnames[de]=ngrams-de-20150819.zip
ngrams_filesnames[es]=ngrams-es-20150915.zip
ngrams_filesnames[fr]=ngrams-fr-20150913.zip
ngrams_filesnames[nl]=ngrams-nl-20181229.zip

download_and_extract_ngrams(){
  local _LANG="${1}"
  local _BASE_URL="https://languagetool.org/download/ngram-data"

  if [ ! -d "${langtool_languageModel}/${_LANG}" ]; then
    if [ ! -e "${langtool_languageModel}\ngrams-${_LANG}.zip" ]; then
      echo "INFO: Downloading \"${_LANG}\" ngrams."
      curl --output "${langtool_languageModel}\ngrams-${_LANG}.zip" "${_BASE_URL}/${ngrams_filesnames[${_LANG}]}"
    fi
    if [ -e "${langtool_languageModel}\ngrams-${_LANG}.zip" ]; then
      echo "INFO: Extracting \"${_LANG}\" ngrams."
      unzip  "${langtool_languageModel}\ngrams-${_LANG}.zip" -d "${langtool_languageModel}"
      rm "${langtool_languageModel}\ngrams-${_LANG}.zip"
    fi
  else
    echo "INFO: Skipping download of ngrams model for language ${_LANG}: already exists."
  fi
  if [ ! -z "${langtool_languageModel}" ]; then
    fix_dir_owner "${langtool_languageModel}/${_LANG}/"
  fi
}

handle_ngrams(){
  if [ ! -z "${langtool_languageModel}" ]; then
    if [ ! -z "${download_ngrams_for_langs}" ] && [ ! -z "${langtool_languageModel}" ] ; then
      IFS=',' read -ra langs <<< "${download_ngrams_for_langs}"
      for lang in "${langs[@]}"; do
        case "${lang}" in
          en|de|es|fr|nl)
            download_and_extract_ngrams "${lang}"
            ;;
          none)
            ;;
          *)
            echo "ERROR: Unknown ngrams language. Supported languages are \"en\", \"de\", \"es\", \"fr\" and \"nl\"."
            exit 1
        esac
      done
	fi
  else
    if [ ! -z "${download_ngrams_for_langs}" ]; then
      echo "WARNING: No base path for ngram language modules provided, skipping download of ${download_ngrams_for_langs}."
	else
	  echo "WARNING: No base path for ngram language modules provided." 
	fi
  fi
}

download_fasttext_mode(){
  if [ ! -z "${langtool_fasttextModel}" ];then
    if [ ! -e "${langtool_fasttextModel}" ]; then
      echo "INFO: Downloading fasttext model."
      curl --output "${langtool_fasttextModel}" "https://dl.fbaipublicfiles.com/fasttext/supervised-models/lid.176.bin"
      fix_dir_owner "${langtool_fasttextModel}"
	else
	  echo "INFO: Skipping download of fasttext model: already exists."
	fi
  else
    echo "INFO: \"langtool_fasttextModel\" not specified. Skipping download of fasttext model."
    unset langtool_fasttextModel
  fi
}

fix_ownership(){
  if [ ! -z "${langtool_languageModel}" ]; then
    echo "INFO: Fixing ownership for ngrams base folder if necessary."
    fix_dir_owner "${langtool_languageModel}"
  fi
  if [ ! -z "${langtool_fasttextModel}" ]; then
    echo "INFO: Fixing ownership for fasttext model file if necessasry."
    fix_dir_owner "$(dirname "${langtool_fasttextModel}")"
  fi
}

create_config(){
  echo "INFO: Creating new LanguageTool config file."

  if [ -e config.properties ]; then
    rm config.properties
    touch config.properties
  fi 

  for varname in ${!langtool_*}; do
    config_injected=true
    echo "${varname#'langtool_'}="${!varname} >> config.properties
  done
}

user_map(){
  if [ ! -z "${MAP_UID}" ]; then
    echo "INFO: Changing uid for user \"languagetool\" to ${MAP_UID}."
    usermod -u ${MAP_UID} languagetool
  fi
  if [ ! -z "${MAP_GID}" ]; then
    echo "INFO: Changing gid for group \"languagetool\" to ${MAP_GID}."
    groupmod -g ${MAP_GID} languagetool 
  fi
}

user_map
fix_ownership
handle_ngrams
download_fasttext_mode
create_config

# show current languagetool config
if [ "$config_injected" = true ] ; then
  echo 'INFO: Using following LanguageTool configuration:'
	cat config.properties
fi

# set memory limits
Xms=${Java_Xms:-256m}
Xmx=${Java_Xmx:-512m}

# start languagetool
exec su-exec languagetool:languagetool java -Xms$Xms -Xmx$Xmx -cp languagetool-server.jar org.languagetool.server.HTTPServer --port ${LISTEPORT:-8010} --public --allow-origin '*' --config config.properties
