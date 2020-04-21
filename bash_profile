#!/bin/bash

export LANGUAGE=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Adds [home directory]/bin to PATH
if [[ ${PATH} != *${HOME}/bin* ]]; then
  export PATH="${HOME}/bin:${PATH}"
fi

# @see: https://stackoverflow.com/a/21655733/4956096
# check if homebrew is installed

if [ -z "$(command -v brew)" ]; then
  echo "Homebrew should be installed. Please go to https://https://brew.sh and install Homebrew."
  exit 1
fi
# brew command-not-found
if brew command command-not-found-init > /dev/null; then
  eval "$(brew command-not-found-init)";
fi


# Homebrew settings
export HOMEBREW_CASK_OPTS="--appdir=${HOME}/Applications --fontdir=/Library/Fonts"

# Check or install Java
export JAVA_HOME="$(/usr/libexec/java_home -R)"

if [ -z "${GITHUB_BARTHEL}" ]; then
  pushd . || exit
  SCRIPT_PATH="$(dirname "${BASH_SOURCE[0]}")"
  # symbolic link check
  if [ -h "${SCRIPT_PATH}" ]; then
    while [ -h "${SCRIPT_PATH}" ];
    do
      cd "$(dirname "$SCRIPT_PATH")" || return
      SCRIPT_PATH=$(readlink "${SCRIPT_PATH}")
    done
  fi
  cd "$(dirname "${SCRIPT_PATH}")/.." || exit
  # export private github.com (https://github.com/barthel) repository path
  export GITHUB_BARTHEL=$(pwd);
  # export github.com repository base path
  # @see: http://wiki.bash-hackers.org/syntax/pe
  export GITHUB_BASE="${GITHUB_BARTHEL%%/barthel}"
  popd || exit
fi

# Adds defined repositories located in GITHUB_BARTHEL to PATH
if [[ ${PATH} != *${GITHUB_BARTHEL}* ]]; then
  export PATH="${GITHUB_BARTHEL}/git-utils:${GITHUB_BARTHEL}/maven-utils:${PATH}"
fi

# bash completion

# brew install bash-completion
if [ -f "$(brew --prefix)/etc/bash_completion" ]; then
  # shellcheck source=/usr/local//etc/bash_completion
  . "$(brew --prefix)/etc/bash_completion"
fi

# git prompt
if [ -f "$(brew --prefix bash-git-prompt)/share/gitprompt.sh" ]; then
  __GIT_PROMPT_DIR="$(brew --prefix bash-git-prompt)/share"
  # shellcheck source=/usr/local/opt/bash-git-prompt/share/gitprompt.sh
  . "$(brew --prefix bash-git-prompt)/share/gitprompt.sh"
fi


# aliases
alias ll='ls -l'
alias la='ls -al'
alias less="LESS='-RS#3M~g' less"
alias less_n="LESS='-RS#3NM~g' less"

alias brew_update="brew update && brew update && brew upgrade && brew cask upgrade && brew cleanup"

# IntelliJ IDEA convenient CLI commands/functions
IDEA_CLI="/usr/local/bin/idea"

if [ -x "${IDEA_CLI}" ]; then
  function idea_issue_review () { for i in $(git issue-files-only "$@"); do if [ -f "${i}" ]; then if [[ "${i}" =~ ^.*pom\.xml ]]; then echo "Open ${i} manually."; else ${IDEA_CLI} "${i}"; fi; fi; done; }
  function idea_commit_review () { for i in $(git show --pretty=format: --name-only  "$@" | sort |uniq | xargs file -Nn -- | grep -v ERROR | cut -d':' -f1); do if [ -f "${i}" ]; then if [[ "${i}" =~ ^.*pom\.xml ]]; then echo "Open ${i} manually."; else ${IDEA_CLI} "${i}"; fi; fi; done; }
  function idea_open () { for i in "${@}"; do if [ -f "${i}" ]; then if [[ "${i}" =~ ^.*pom\.xml ]]; then echo "Open ${i} manually."; else ${IDEA_CLI} "${i}"; fi; fi; done; }
fi

if [ -n "${ECLIPSE_APP}" ]; then
  export ECLIPSE_CLI="open -g -a ${ECLIPSE_APP} "
  # Enhances open command with Eclipse command line arguments like Workspace:
  # ECLIPSE_CLI_ARGS=" --args -data ${ECLIPSE_WORKSPACE} "
  # Append these arguments behind the file:
  # ${ECLIPSE_CLI} "${i}" ${ECLIPSE_CLI_ARGS}
  function eclipse_issue_review () { for i in $(git issue-files-only "$@"); do if [ -f "${i}" ]; then ${ECLIPSE_CLI} "${i}"; fi; done; }
  function eclipse_commit_review () { for i in $(git show --pretty=format: --name-only  "$@" | sort |uniq | xargs file -Nn -- | grep -v ERROR | cut -d':' -f1); do if [ -f "${i}" ]; then ${ECLIPSE_CLI} "${i}"; fi; done; }
  function eclipse_open () { for i in "${@}"; do if [ -f "${i}" ]; then ${ECLIPSE_CLI} "${i}"; fi; done; }
fi