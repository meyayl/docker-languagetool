#!/bin/bash
set -eo pipefail

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
      echo "Downloading \"${_LANG}\" ngrams"
      curl --output "${langtool_languageModel}\ngrams-${_LANG}.zip" "${_BASE_URL}/${ngrams_filesnames[${_LANG}]}"
    fi
    if [ -e "${langtool_languageModel}\ngrams-${_LANG}.zip" ]; then
      echo "Extracting \"${_LANG}\" ngrams"
      unzip  "${langtool_languageModel}\ngrams-${_LANG}.zip" -d "${langtool_languageModel}"
      rm "${langtool_languageModel}\ngrams-${_LANG}.zip"
    fi
  fi
  find "${langtool_languageModel}/${_LANG}/"  ! -user  languagetool  -exec chown languagetool:languagetool {} \;
}

handle_ngrams(){
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
          echo "Unknown ngrams language. Supported languages are \"en\", \"de\", \"es\", \"fr\" and \"nl\"."
          exit 1
      esac
    done
  fi
}

download_fasttext_mode(){
  if [ ! -e "${langtool_fasttextModel}" ]; then
    curl --output "${langtool_fasttextModel}" "https://dl.fbaipublicfiles.com/fasttext/supervised-models/lid.176.bin"
    find "${langtool_fasttextModel}"  ! -user  languagetool  -exec chown languagetool:languagetool {} \;
  fi
}

fix_ownership(){
  find "${langtool_languageModel}"  ! -user  languagetool  -exec chown languagetool:languagetool {} \;
  if [ "${langtool_fasttextModel}" ];then
    find "$(dirname "${langtool_fasttextModel}")"  ! -user  languagetool  -exec chown languagetool:languagetool {} \;
  fi
}

create_config(){
  if [ -e config.properties ];then
    rm config.properties
    touch config.properties
  fi 

  for varname in ${!langtool_*}; do
    config_injected=true
    echo "${varname#'langtool_'}="${!varname} >> config.properties
  done
}

fix_ownership
handle_ngrams
download_fasttext_mode

# create languagetool config
create_config

# show current languagetool config
if [ "$config_injected" = true ] ; then
  echo 'Using following configuration:'
	cat config.properties
fi

# set memory limits
Xms=${Java_Xms:-256m}
Xmx=${Java_Xmx:-512m}

# start languagetool
exec su-exec languagetool:languagetool java -Xms$Xms -Xmx$Xmx -cp languagetool-server.jar org.languagetool.server.HTTPServer --port 8010 --public --allow-origin '*' --config config.properties
