#!/usr/bin/env bash
# ai-setup: bootstrap and hotwire AI CLI tools to ~/.ai and ~/.ai/laws
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
source "$SCRIPT_DIR/../lib/ai-tools.sh"

# AI_ROOT is the repo checkout; skills live in its skills/ subdirectory and laws
# in laws/. Tools are linked at those subdirectories, never at the repo root --
# a tool's skills root must contain <skill>/SKILL.md directly.
AI_ROOT="${AI_ROOT:-$HOME/.ai}"
AI_SKILLS="${AI_SKILLS:-$AI_ROOT/skills}"
AI_LAWS="${AI_LAWS:-$AI_ROOT/laws}"
AI_REPO="${AI_REPO:-git@github.com:clintgeek/ai-skills.git}"
GLOBAL_RULES="$AI_LAWS/global_rules.md"

# backup_path/ensure_dir are shared with machine-setup via POSIX sh rather than
# retyped per language. Sourced after AI_ROOT is set: backup_path uses it to
# tell our own symlinks (safe to replace) from someone else's (always backed up).
source "$REPO_ROOT/lib/fs-helpers.sh"

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
  select [--clis <list>] [--yes]
                       Show the AI CLI roster, pick one or more, install and
                       hotwire them. <list> takes numbers and/or names (comma
                       or space separated) or "all" for non-interactive use.

Environment:
  AI_ROOT, AI_SKILLS, AI_LAWS, AI_REPO can override defaults.
EOF
}

log() {
  echo "[ai-setup] $*"
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
  if [[ ! -d "$AI_ROOT/.git" ]]; then
    ensure_dir "$(dirname "$AI_ROOT")"
    log "  cloning $AI_REPO into $AI_ROOT"
    git clone "$AI_REPO" "$AI_ROOT"
  else
    log "  $AI_ROOT already a git repo"
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
    local skills_root="${TOOL_SKILLS[$t]:-}"
    local laws_root="${TOOL_LAWS[$t]:-}"
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

# The repo has to exist before anything is linked at it. Without this,
# link_laws creates a starter $GLOBAL_RULES, which makes $AI_ROOT exist,
# non-empty, and not a git checkout -- and machine-setup's setup_repos then
# refuses to clone over it for good, permanently wedging the re-run path with
# placeholder laws in place of THE_SAGE_LAWS. Fail loudly instead.
require_repo() {
  if [[ ! -d "$AI_SKILLS" ]]; then
    log "  $AI_SKILLS does not exist -- the skills repo is not checked out."
    log "  Clone it first:  ai-setup.sh clone"
    log "  Refusing to link tools at a missing repo (that would strand them on"
    log "  dangling symlinks and a placeholder laws file)."
    exit 1
  fi
  if [[ ! -d "$AI_ROOT/.git" ]]; then
    log "  warning: $AI_ROOT is not a git checkout; skills will not update with git pull"
  fi
}

cmd_hotwire() {
  local t="$1"
  log "hotwire $t"
  require_repo
  # Index the registry only through :- defaults: under `set -u` a bare
  # ${TOOL_SKILLS[$t]} on an unknown tool aborts with "unbound variable"
  # before the friendly message below can ever be printed.
  local skills_root="${TOOL_SKILLS[$t]:-}"
  local laws_root="${TOOL_LAWS[$t]:-}"
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
  require_repo
  if ! command -v "$t" >/dev/null 2>&1; then
    log "  $t not installed. Install it first."
    exit 1
  fi
  link_skills "$skills"
  link_laws "$laws"
  log "  $t hotwired"
}

# Interactive (or --clis) multi-select: pick AI CLIs, install them, hotwire them.
# This is machine-setup's hand-off point -- installing the CLIs IS the job on a
# fresh machine, so it gets a roster and a choice rather than installing four
# vendors' scripts by fiat.
cmd_select() {
  local yes=false clis=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes) yes=true; shift ;;
      --clis)
        [[ $# -lt 2 ]] && { echo "Error: --clis requires an argument" >&2; exit 1; }
        clis="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown select option: $1" >&2; exit 1 ;;
    esac
  done

  log "select AI CLIs"
  if [[ -z "$clis" ]]; then
    tool_roster
    if [[ ! -t 0 ]]; then
      log "Non-interactive: pass --clis <numbers|names|all> to choose without a prompt."
      return 0
    fi
    echo "Pick the CLIs to install and hotwire."
    echo "Numbers and/or names, comma or space separated. 'all' for everything."
    echo "Press Enter to install nothing and only hotwire what is already present."
    printf "> "
    read -r clis || clis=""
  fi

  local -a chosen
  chosen=()
  local t
  while IFS= read -r t; do
    [[ -n "$t" ]] && chosen+=("$t")
  done < <(resolve_tool_selection "$clis")

  # Nothing chosen: still hotwire every CLI already on the machine, which is the
  # point of running this at all.
  if [[ ${#chosen[@]} -eq 0 ]]; then
    log "  no CLIs selected for install; hotwiring what is already installed"
    for t in "${AI_TOOLS[@]}"; do
      command -v "$t" >/dev/null 2>&1 || continue
      [[ "${TOOL_KNOWN[$t]:-0}" -eq 1 ]] || { log "  $t installed but has no vetted path map; use hotwire-generic"; continue; }
      cmd_hotwire "$t" || log "  hotwire of $t failed"
    done
    return 0
  fi

  local installed_any=false
  for t in "${chosen[@]}"; do
    if tool_install_one "$t" "$yes"; then
      installed_any=true
      if [[ "${TOOL_KNOWN[$t]:-0}" -eq 1 ]]; then
        cmd_hotwire "$t" || log "  hotwire of $t failed"
      else
        log "  $t has no vetted path map; hotwire it with: ai-setup.sh hotwire-generic $t <skills> <laws>"
      fi
    fi
  done
  [[ "$installed_any" == true ]] || log "  nothing was installed"
  return 0
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
    select)
      cmd_select "$@"
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
