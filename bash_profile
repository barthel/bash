#! /usr/bin/env bash

export LANGUAGE=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Adds [home directory]/bin to PATH
if [[ ${PATH} != *${HOME}/bin* ]]; then
  export PATH="${HOME}/bin:${PATH}"
fi

################################################################################
## Homebrew configuration
# @see: https://stackoverflow.com/a/21655733/4956096
################################################################################
# check if homebrew is installed

# Homebrew ist optional. Pfade direkt prüfen, da `command -v brew` in einer kalten Shell
# (frisches Terminal-Fenster) scheitern kann, bevor `brew shellenv` den PATH ergänzt.
BREW_BIN=""
if [ -x /opt/homebrew/bin/brew ]; then
  BREW_BIN="/opt/homebrew/bin/brew"
elif [ -x /usr/local/bin/brew ]; then
  BREW_BIN="/usr/local/bin/brew"
elif command -v brew &>/dev/null; then
  BREW_BIN="$(command -v brew)"
fi

if [ -n "${BREW_BIN}" ]; then
  eval "$("${BREW_BIN}" shellenv)"
  # brew command-not-found
  if "${BREW_BIN}" command command-not-found-init > /dev/null 2>&1; then
    eval "$("${BREW_BIN}" command-not-found-init)";
  fi
  # Homebrew settings
  export HOMEBREW_NO_ANALYTICS=1
  export HOMEBREW_CASK_OPTS="--appdir=${HOME}/Applications --fontdir=/Library/Fonts"
  alias brew_update="brew update && brew update && brew upgrade && brew upgrade --cask && brew cleanup"
  HOMEBREW_NO_ENV_HINTS=true
fi

################################################################################
## JAVA base configuration
################################################################################
# Check or install Java
export JAVA_HOME="$(/usr/libexec/java_home)"

if [ -z "${GITHUB_BARTHEL}" ]; then
  _OLDPWD="$(pwd)"
  SCRIPT_PATH="$(dirname "${BASH_SOURCE[0]:-$0}")"
  # symbolic link check
  if [ -h "${SCRIPT_PATH}" ]; then
    while [ -h "${SCRIPT_PATH}" ]; do
      cd "$(dirname "$SCRIPT_PATH")" || return
      SCRIPT_PATH=$(readlink "${SCRIPT_PATH}")
    done
  fi
  cd "$(dirname "${SCRIPT_PATH}")/.." || return
  # export private github.com (https://github.com/barthel) repository path
  export GITHUB_BARTHEL=$(pwd)
  # export github.com repository base path
  # @see: http://wiki.bash-hackers.org/syntax/pe
  export GITHUB_BASE="${GITHUB_BARTHEL%%/barthel}"
  cd "${_OLDPWD}" || return
  unset _OLDPWD SCRIPT_PATH
fi

# Adds defined repositories located in GITHUB_BARTHEL to PATH
if [[ ${PATH} != *${GITHUB_BARTHEL}* ]]; then
  export PATH="${GITHUB_BARTHEL}/git-utils:${GITHUB_BARTHEL}/maven-utils:${PATH}"
fi

################################################################################
## Bash configuration
################################################################################
# Disables the bash deprecation warning
# @see: https://www.addictivetips.com/mac-os/hide-default-interactive-shell-is-now-zsh-in-terminal-on-macos/
export BASH_SILENCE_DEPRECATION_WARNING=1

# starship bash prompt
# check and configure starship bash prompt
if [ -z "$(command -v starship)" ]; then
  echo "Warning: starship not found -- install via 'port install starship'."
else
  if [ -f "${GITHUB_BARTHEL}/bash/starship_config.toml" ]; then
    export STARSHIP_CONFIG="${GITHUB_BARTHEL}/bash/starship_config.toml"
  fi
  eval "$(starship init bash)"
fi

# brew install bash-completion
if [ -n "${BREW_BIN}" ]; then
  _brew_prefix="$("${BREW_BIN}" --prefix)"
  # shellcheck source=/opt/homebrew/etc/bash_completion
  [[ -r "${_brew_prefix}/etc/profile.d/bash_completion.sh" ]] && . "${_brew_prefix}/etc/profile.d/bash_completion.sh"
  [[ -r "${_brew_prefix}/etc/profile.d/bash_completion" ]] && . "${_brew_prefix}/etc/profile.d/bash_completion"
  unset _brew_prefix
fi

################################################################################
# aliases
alias ll='ls -l'
alias la='ls -al'
alias less="LESS='-RS#3M~g' less"
alias less_n="LESS='-RS#3NM~g' less"


################################################################################
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

function console_issue_review () { for i in $(git issue "$@" | cut -d' ' -f2 | tac); do git show "${i}"; echo; read -rsn1 -p "Press ESC key to abort" key; if [[ $key == $'\e' ]]; then echo; break; fi; done; }

################################################################################
# Mistral Vibe CLI wrapper (tmux-Statuszeile)
################################################################################
function vibe () {
  "${ITERATEC_UBARTHEL}/ai-cli/vibe/bin/vibe-wrapper" "$@"
}
