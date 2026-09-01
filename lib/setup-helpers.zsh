#!/usr/bin/env zsh
# Shared helpers for machine-setup.

: "${BACKUP_TIMESTAMP:=$(date +%Y%m%d-%H%M%S)}"

_log_helper() {
  if (( $+functions[log] )); then
    log "$@" >&2
  else
    echo "$@" >&2
  fi
}

backup_path() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    local bak="${path}.bak-${BACKUP_TIMESTAMP}"
    _log_helper "  backing up $path -> $bak"
    mv "$path" "$bak"
    echo "$bak"
  else
    echo ""
  fi
}

ensure_dir() {
  local d="$1"
  if [[ ! -d "$d" ]]; then
    mkdir -p "$d"
    _log_helper "  created $d"
  fi
}
