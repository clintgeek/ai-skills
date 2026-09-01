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
  for mgr in apt-get apt dnf yum pacman zypper apk; do
    if command -v "$mgr" >/dev/null 2>&1; then
      PKG_MGR="$mgr"
      return 0
    fi
  done
  PKG_MGR=""
}
[[ "$OS_KIND" == "linux" ]] && detect_pkg_mgr

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
    mac)     echo "${APP_INSTALL_MAC[$app]:-}" ;;
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

preselect_apps() {
  local role="$1" categories="$2" extras="$3"
  local app tags t c
  SELECTED_APPS=()
  for app in "${APPS[@]}"; do
    tags=( ${(s:,:)APP_TAGS[$app]:-} )
    local include=false
    for t in $tags; do
      [[ "$t" == "base" ]] && include=true
      [[ -n "$role" && "$t" == "$role" ]] && include=true
    done
    if [[ -n "$categories" ]]; then
      local cats=( ${(s:,:)categories} )
      for c in $cats; do
        for t in $tags; do
          [[ "$t" == "$c" ]] && include=true
        done
      done
    fi
    [[ "$include" == true ]] && SELECTED_APPS+=("$app")
  done
  if [[ -n "$extras" ]]; then
    local ex=( ${(s:,:)extras} )
    for app in $ex; do
      if [[ " ${SELECTED_APPS[@]} " != *" $app "* ]]; then
        SELECTED_APPS+=("$app")
      fi
    done
  fi
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
      log "installing $tool if missing..."
      "$REPO_ROOT/skills/ai-setup/scripts/ai-setup.sh" install "$tool" --yes || log "  install of $tool failed"
      log "hotwiring $tool..."
      "$REPO_ROOT/skills/ai-setup/scripts/ai-setup.sh" hotwire "$tool" || log "  hotwire of $tool failed"
    fi
  done
}
