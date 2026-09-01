#!/usr/bin/env zsh
# Shared helpers for machine-setup.
# Sourced by skills/machine-setup/scripts/machine-wizard.zsh.
# The caller must set REPO_ROOT before sourcing.

[[ -n "${REPO_ROOT:-}" ]] || { echo "REPO_ROOT must be set before sourcing lib/machine-setup.zsh" >&2; return 1; }

source "$REPO_ROOT/lib/app-catalog.zsh"
source "$REPO_ROOT/skills/machine-setup/repos.conf"
source "$REPO_ROOT/skills/ai-setup/lib/ai-tools.sh"
source "$REPO_ROOT/lib/setup-helpers.zsh"

log() {
  echo "[machine-setup] $*"
}

PKG_MGR=""
detect_pkg_mgr() {
  local mgr
  # macOS has no system package manager, so brew IS the package manager there.
  # Every APP_INSTALL_MAC entry is a `brew install`, so without brew the mac
  # install step cannot do anything at all.
  if [[ "$OS_KIND" == "mac" ]]; then
    if command -v brew >/dev/null 2>&1; then
      PKG_MGR="brew"
    else
      PKG_MGR=""
    fi
    return 0
  fi
  for mgr in apt-get apt dnf yum pacman zypper apk; do
    if command -v "$mgr" >/dev/null 2>&1; then
      PKG_MGR="$mgr"
      return 0
    fi
  done
  PKG_MGR=""
}
detect_pkg_mgr

linux_pkg_name() {
  local app="$1"
  case "$PKG_MGR" in
    apt-get|apt) echo "${APP_PACKAGE_APT[$app]:-${APP_PACKAGE_LINUX[$app]:-}}" ;;
    *)           echo "${APP_PACKAGE_LINUX[$app]:-}" ;;
  esac
}

linux_install_cmd() {
  local app="$1" pkg
  if [[ -z "$PKG_MGR" ]]; then
    echo ""
    return 0
  fi
  pkg="$(linux_pkg_name "$app")"
  if [[ -z "$pkg" ]]; then
    echo ""
    return 0
  fi
  case "$PKG_MGR" in
    apt-get|apt|dnf|yum) echo "sudo $PKG_MGR install -y $pkg" ;;
    pacman)              echo "sudo pacman -S --noconfirm $pkg" ;;
    zypper)              echo "sudo zypper install -y $pkg" ;;
    apk)                 echo "sudo apk add --no-cache $pkg" ;;
    *)                   echo "" ;;
  esac
  return 0
}

install_cmd() {
  local app="$1" cmd
  case "$OS_KIND" in
    mac)
      # Every mac entry is a brew command; with no brew there is nothing to run.
      # scripts/machine-wizard bootstraps brew before we get here, but the .zsh
      # wizard can also be invoked directly.
      if [[ -z "$PKG_MGR" ]]; then
        echo ""
      else
        echo "${APP_INSTALL_MAC[$app]:-}"
      fi
      ;;
    linux)
      cmd="${APP_INSTALL_LINUX[$app]:-}"
      if [[ -n "$cmd" ]]; then
        echo "$cmd"
      else
        linux_install_cmd "$app"
      fi
      ;;
    windows) echo "${APP_INSTALL_WINDOWS[$app]:-}" ;;
    *)       echo "" ;;
  esac
  return 0
}

# ---------------------------------------------------------------------------
# Selection items
# ---------------------------------------------------------------------------
# A selection item is a TYPED string, so nothing has to be guessed from its
# shape. The old scheme kept bare app ids and decided "does it contain a space?"
# to tell an app from a raw shell command -- which silently dropped every
# single-token custom app and eval'd any typo that happened to contain a space.
#
#   app:<catalog-id>   an entry in lib/app-catalog.zsh
#   pkg:<name>         a bare package name for the detected package manager
#   cmd:<raw command>  a raw command, run verbatim, never split or reinterpreted

item_kind()  { echo "${1%%:*}"; }
item_value() { echo "${1#*:}"; }

item_label() {
  local kind="$(item_kind "$1")" value="$(item_value "$1")"
  case "$kind" in
    app) echo "${APP_NAME[$value]:-$value}" ;;
    pkg) echo "$value (package)" ;;
    cmd) echo "$value" ;;
    *)   echo "$1" ;;
  esac
}

# Install command for a bare package name, per OS/package manager.
pkg_install_cmd() {
  local pkg="$1"
  case "$OS_KIND" in
    mac)
      [[ -z "$PKG_MGR" ]] && { echo ""; return 0; }
      echo "brew install $pkg" ;;
    windows) echo "winget install --id $pkg --accept-package-agreements --accept-source-agreements" ;;
    *)
      case "$PKG_MGR" in
        apt-get|apt|dnf|yum) echo "sudo $PKG_MGR install -y $pkg" ;;
        pacman)              echo "sudo pacman -S --noconfirm $pkg" ;;
        zypper)              echo "sudo zypper install -y $pkg" ;;
        apk)                 echo "sudo apk add --no-cache $pkg" ;;
        *)                   echo "" ;;
      esac ;;
  esac
  return 0
}

item_install_cmd() {
  local kind="$(item_kind "$1")" value="$(item_value "$1")"
  case "$kind" in
    app) install_cmd "$value" ;;
    pkg) pkg_install_cmd "$value" ;;
    cmd) echo "$value" ;;
    *)   echo "" ;;
  esac
}

# Turn user input from --extras or the interactive checklist into a typed item.
# A catalog id wins; anything containing shell syntax is a raw command;
# everything else is a package name for the local package manager. Nothing is
# ever dropped on the floor.
classify_extra() {
  local raw="${1## }"
  raw="${raw%% }"
  [[ -z "$raw" ]] && return 1
  if [[ -n "${APP_NAME[$raw]:-}" ]]; then
    echo "app:$raw"
    return 0
  fi
  # Shell syntax, whitespace, or a leading path all mean "run this verbatim".
  if [[ "$raw" == *[[:space:]]* || "$raw" == *[\|\&\;\$\(\)\<\>\*\"\']* || "$raw" == /* || "$raw" == .* ]]; then
    echo "cmd:$raw"
    return 0
  fi
  echo "pkg:$raw"
  return 0
}

# How many catalog apps carry a given role. Used to warn about a role that
# would silently select nothing but `base`.
role_app_count() {
  local role="$1" app t n=0
  for app in "${APPS[@]}"; do
    for t in ${(s:,:)APP_ROLES[$app]:-}; do
      # NOT (( n++ )): that evaluates to the pre-increment value, so the first
      # increment from 0 returns 0, which is a non-zero exit status and aborts
      # the caller under `set -e`.
      [[ "$t" == "$role" ]] && n=$(( n + 1 ))
    done
  done
  echo "$n"
}

# Build SELECTED_APPS from roles + categories. Roles and categories are now
# distinct axes (APP_ROLES vs APP_TAGS); previously both were matched against a
# single tag list, so `--role dev` and `--categories dev` were the same thing
# while `--role admin`/`--role general` matched nothing.
#   roles      comma-separated list (may be empty)
#   categories comma-separated list (may be empty)
preselect_apps() {
  local roles="$1" categories="$2"
  local app t r c
  local -a role_list cat_list
  role_list=( ${(s:,:)roles} )
  cat_list=( ${(s:,:)categories} )
  SELECTED_APPS=()
  for app in "${APPS[@]}"; do
    local include=false
    # `base` is the always-on layer.
    for t in ${(s:,:)APP_TAGS[$app]:-}; do
      [[ "$t" == "base" ]] && include=true
    done
    for r in $role_list; do
      [[ -z "$r" ]] && continue
      for t in ${(s:,:)APP_ROLES[$app]:-}; do
        [[ "$t" == "$r" ]] && include=true
      done
    done
    for c in $cat_list; do
      [[ -z "$c" ]] && continue
      for t in ${(s:,:)APP_TAGS[$app]:-}; do
        [[ "$t" == "$c" ]] && include=true
      done
    done
    [[ "$include" == true ]] && SELECTED_APPS+=("app:$app")
  done
}

# Append extras without duplicating anything already selected.
add_extras() {
  local item raw
  for raw in "$@"; do
    item="$(classify_extra "$raw")" || continue
    [[ -z "$item" ]] && continue
    if (( ! ${SELECTED_APPS[(Ie)$item]} )); then
      SELECTED_APPS+=("$item")
    fi
  done
}

setup_repos() {
  local id path url post was_cloned
  for id in "${MACHINE_REPOS[@]}"; do
    path="${REPO_PATH[$id]:-}"
    url="${REPO_URL[$id]:-}"
    post="${REPO_POST_CLONE[$id]:-}"
    if [[ -z "$path" ]]; then
      log "skipping repo $id: no path configured"
      continue
    fi
    if [[ -n "${REPO_ROOT:-}" && "$path" == "$REPO_ROOT" ]]; then
      log "skipping active repo $path"
      continue
    fi
    if [[ "$id" == "ai" && ! -d "$path/.git" && -d "$path" && -n "$(ls -A "$path" 2>/dev/null)" ]]; then
      log "skipping $id repo ($path) because it exists, is not a git checkout, and may contain tool configs; please move or back it up manually"
      continue
    fi
    was_cloned=false
    local bak=""
    if [[ -d "$path/.git" ]]; then
      log "pulling ${REPO_NAME[$id]:-$id}..."
      git -C "$path" pull --ff-only || log "  pull failed, continuing"
    else
      if [[ -e "$path" || -L "$path" ]]; then
        bak="$(backup_path "$path" 2>/dev/null)" || { log "  backup of $path failed, skipping"; continue; }
      fi
      log "cloning ${REPO_NAME[$id]:-$id} to $path..."
      if git clone "$url" "$path"; then
        was_cloned=true
      else
        log "  clone of ${REPO_NAME[$id]:-$id} failed"
        if [[ -n "$bak" ]]; then
          log "  restoring $path from $bak"
          rm -rf "$path"
          mv "$bak" "$path"
        fi
        continue
      fi
    fi
    if [[ "$was_cloned" == true && -n "$post" ]]; then
      log "running post-clone for ${REPO_NAME[$id]:-$id}: $post"
      if (cd "$path" && eval "$post"); then
        :
      else
        log "  post-clone for ${REPO_NAME[$id]:-$id} failed"
      fi
    fi
  done
}

setup_ai_clis() {
  local tool
  for tool in "${AI_TOOLS[@]}"; do
    if [[ "${TOOL_KNOWN[$tool]:-0}" -eq 1 ]]; then
      # Go through the sh wrapper, not ai-setup.sh directly: it needs bash 4+
      # and a fresh Mac only has bash 3.2 until the bootstrapper installs one.
      log "installing $tool if missing..."
      "$REPO_ROOT/skills/ai-setup/scripts/ai-setup" install "$tool" --yes || log "  install of $tool failed"
      log "hotwiring $tool..."
      "$REPO_ROOT/skills/ai-setup/scripts/ai-setup" hotwire "$tool" || log "  hotwire of $tool failed"
    fi
  done
}
