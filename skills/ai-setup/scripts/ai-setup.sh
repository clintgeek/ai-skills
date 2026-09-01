#!/usr/bin/env bash
# ai-setup: bootstrap and hotwire AI CLI tools to ~/.ai and ~/.ai/laws
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/ai-tools.sh"

AI_SKILLS="${AI_SKILLS:-$HOME/.ai}"
AI_LAWS="${AI_LAWS:-$HOME/.ai/laws}"
AI_REPO="${AI_REPO:-git@github.com:clintgeek/ai-skills.git}"
GLOBAL_RULES="$AI_LAWS/global_rules.md"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

usage() {
  cat << 'EOF'
Usage: ai-setup.sh <command> [args]

Commands:
  clone                Clone or verify ~/.ai and create ~/.ai/laws
  inventory            Show which tools are installed and hotwired
  hotwire <tool>       Hotwire a known tool's skills + laws
  hotwire-generic <tool> <skills-path> <laws-path>
                       Hotwire any tool with explicit paths
  install <tool> [--yes]
                       Show install command for a tool; --yes runs it

Environment:
  AI_SKILLS, AI_LAWS, AI_REPO can override defaults.
EOF
}

log() {
  echo "[ai-setup] $*"
}

backup_path() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    local bak="${path}.bak-${TIMESTAMP}"
    log "  backing up $path -> $bak"
    mv "$path" "$bak"
  fi
}

ensure_dir() {
  local d="$1"
  if [[ ! -d "$d" ]]; then
    mkdir -p "$d"
    log "  created $d"
  fi
}

link_skills() {
  local target="$1"
  if [[ -L "$target" && "$(readlink "$target")" == "$AI_SKILLS" ]]; then
    return 0
  fi
  backup_path "$target"
  ensure_dir "$(dirname "$target")"
  ln -s "$AI_SKILLS" "$target"
  log "  linked $target -> $AI_SKILLS"
}

link_laws() {
  local target="$1"
  if [[ -L "$target" && "$(readlink "$target")" == "$GLOBAL_RULES" ]]; then
    return 0
  fi
  backup_path "$target"
  ensure_dir "$(dirname "$target")"
  ensure_dir "$AI_LAWS"
  if [[ ! -f "$GLOBAL_RULES" ]]; then
    cat > "$GLOBAL_RULES" << 'EOF'
# Global AI Laws

These rules apply to every AI tool hotwired to `~/.ai/laws`.
Add always-on behavior, tone, and hard constraints here.
EOF
    log "  created starter $GLOBAL_RULES"
  fi
  ln -s "$GLOBAL_RULES" "$target"
  log "  linked $target -> $GLOBAL_RULES"
}

cmd_clone() {
  log "clone"
  if [[ ! -d "$AI_SKILLS/.git" ]]; then
    ensure_dir "$(dirname "$AI_SKILLS")"
    log "  cloning $AI_REPO into $AI_SKILLS"
    git clone "$AI_REPO" "$AI_SKILLS"
  else
    log "  $AI_SKILLS already a git repo"
  fi
  ensure_dir "$AI_LAWS"
  if [[ ! -f "$GLOBAL_RULES" ]]; then
    cat > "$GLOBAL_RULES" << 'EOF'
# Global AI Laws

These rules apply to every AI tool hotwired to `~/.ai/laws`.
Add always-on behavior, tone, and hard constraints here.
EOF
    log "  created starter $GLOBAL_RULES"
  else
    log "  $GLOBAL_RULES already exists"
  fi
}

cmd_inventory() {
  log "inventory"
  printf "\n%-14s %-10s %-8s %-8s %-8s\n" "tool" "installed" "known" "skills" "laws"
  local t
  for t in "${AI_TOOLS[@]}"; do
    local installed="no" skills="no" laws="no" known="no"
    local skills_root="${TOOL_SKILLS[$t]}"
    local laws_root="${TOOL_LAWS[$t]}"
    if command -v "$t" >/dev/null 2>&1; then
      installed="yes"
    fi
    [[ "${TOOL_KNOWN[$t]:-0}" -eq 1 ]] && known="yes"
    if [[ -L "$skills_root" && "$(readlink "$skills_root")" == "$AI_SKILLS" ]]; then
      skills="yes"
    elif [[ -d "$skills_root" && ! -L "$skills_root" ]]; then
      skills="dir"
    fi
    if [[ -L "$laws_root" && "$(readlink "$laws_root")" == "$GLOBAL_RULES" ]]; then
      laws="yes"
    elif [[ -e "$laws_root" && ! -L "$laws_root" ]]; then
      laws="file"
    fi
    printf "%-14s %-10s %-8s %-8s %-8s\n" "$t" "$installed" "$known" "$skills" "$laws"
  done
}

cmd_hotwire() {
  local t="$1"
  local skills_root="${TOOL_SKILLS[$t]}"
  local laws_root="${TOOL_LAWS[$t]}"
  log "hotwire $t"
  if [[ -z "$skills_root" || "${TOOL_KNOWN[$t]:-0}" -ne 1 ]]; then
    log "  $t has no built-in path map. Use: ai-setup.sh hotwire-generic <tool> <skills-path> <laws-path>"
    exit 1
  fi
  if ! command -v "$t" >/dev/null 2>&1; then
    log "  $t not installed. Install it first with: ai-setup.sh install $t"
    exit 1
  fi
  link_skills "$skills_root"
  link_laws "$laws_root"
  log "  $t hotwired"
}

cmd_hotwire_generic() {
  local t="$1"
  local skills="$2"
  local laws="$3"
  log "hotwire-generic $t"
  if ! command -v "$t" >/dev/null 2>&1; then
    log "  $t not installed. Install it first."
    exit 1
  fi
  link_skills "$skills"
  link_laws "$laws"
  log "  $t hotwired"
}

cmd_install() {
  local t="" yes=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes) yes=true; shift ;;
      -h|--help) usage; exit 0 ;;
      -*) echo "Unknown install option: $1" >&2; exit 1 ;;
      *)
        if [[ -z "$t" ]]; then t="$1"; shift
        else echo "Unexpected argument: $1" >&2; exit 1; fi
        ;;
    esac
  done
  if [[ -z "$t" ]]; then
    usage
    exit 1
  fi
  if [[ ! " ${AI_TOOLS[@]} " =~ " $t " ]]; then
    log "unknown tool: $t"
    exit 1
  fi
  if command -v "$t" >/dev/null 2>&1; then
    log "$t already installed at $(command -v "$t")"
    return 0
  fi
  local cmd note
  cmd="$(install_command "$t")"
  note="$(install_note "$t")"
  log "install $t"
  echo "  $cmd"
  [[ -n "$note" ]] && echo "  $note"
  if [[ "$cmd" == *"(PowerShell)"* ]]; then
    log "PowerShell command; not auto-executable from bash"
    return 0
  fi
  if [[ "$yes" != true ]]; then
    if [[ -t 0 ]]; then
      local answer
      read -r -p "Run it now? [y/N] " answer
      [[ "$answer" =~ ^[Yy]$ ]] || { log "Skipped."; return 0; }
    else
      log "Non-interactive: re-run with --yes, or run the command yourself"
      return 0
    fi
  fi
  log "Installing $t..."
  if bash -c "$cmd"; then
    hash -r 2>/dev/null || true
    if command -v "$t" >/dev/null 2>&1; then
      log "✓ $t installed at $(command -v "$t")"
    else
      log "installer finished but $t not on PATH yet"
    fi
  else
    log "✗ install failed for $t"
    return 1
  fi
}

main() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 1
  fi

  local cmd="$1"
  shift

  case "$cmd" in
    clone)
      cmd_clone
      ;;
    inventory)
      cmd_inventory
      ;;
    hotwire)
      [[ $# -lt 1 ]] && { usage; exit 1; }
      cmd_hotwire "$1"
      ;;
    hotwire-generic)
      [[ $# -lt 3 ]] && { usage; exit 1; }
      cmd_hotwire_generic "$1" "$2" "$3"
      ;;
    install)
      cmd_install "$@"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
