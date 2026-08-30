#!/usr/bin/env bash
# ai-setup: bootstrap and hotwire AI CLI tools to ~/.ai/skills and ~/.ai/laws
set -euo pipefail

AI_SKILLS="${AI_SKILLS:-$HOME/.ai/skills}"
AI_LAWS="${AI_LAWS:-$HOME/.ai/laws}"
AI_REPO="${AI_REPO:-git@github.com:clintgeek/ai-skills.git}"
GLOBAL_RULES="$AI_LAWS/global_rules.md"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

usage() {
  cat << 'EOF'
Usage: ai-setup.sh <command> [args]

Commands:
  clone                Clone or verify ~/.ai/skills and create ~/.ai/laws
  inventory            Show which tools are installed and hotwired
  hotwire <tool>       Hotwire a known tool's skills + laws
  hotwire-generic <tool> <skills-path> <laws-path>
                       Hotwire any tool with explicit paths
  install <tool>       Show install help for a tool (calls ai-battle --connect)

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

tool_info() {
  local t="$1"
  case "$t" in
    devin)
      SKILLS_ROOT="$HOME/.config/devin/skills"
      LAWS_ROOT="$HOME/.config/devin/global_rules.md"
      KNOWN=1
      ;;
    claude)
      SKILLS_ROOT="$HOME/.claude/skills"
      LAWS_ROOT="$HOME/.claude/CLAUDE.md"
      KNOWN=1
      ;;
    agy)
      SKILLS_ROOT="$HOME/.antigravity/skills"
      LAWS_ROOT="$HOME/.antigravity/global_rules.md"
      KNOWN=0
      ;;
    gemini)
      SKILLS_ROOT="$HOME/.gemini/skills"
      LAWS_ROOT="$HOME/.gemini/global_rules.md"
      KNOWN=0
      ;;
    copilot)
      SKILLS_ROOT="$HOME/.copilot/skills"
      LAWS_ROOT="$HOME/.copilot/copilot-instructions.md"
      KNOWN=1
      ;;
    codex)
      SKILLS_ROOT="$HOME/.codex/skills"
      LAWS_ROOT="$HOME/.codex/global_rules.md"
      KNOWN=0
      ;;
    opencode)
      SKILLS_ROOT="$HOME/.opencode/skills"
      LAWS_ROOT="$HOME/.opencode/global_rules.md"
      KNOWN=0
      ;;
    goose)
      SKILLS_ROOT="$HOME/.goose/skills"
      LAWS_ROOT="$HOME/.goose/global_rules.md"
      KNOWN=0
      ;;
    aider)
      SKILLS_ROOT="$HOME/.aider/skills"
      LAWS_ROOT="$HOME/.aider/global_rules.md"
      KNOWN=0
      ;;
    cursor-agent)
      SKILLS_ROOT="$HOME/.cursor/skills"
      LAWS_ROOT="$HOME/.cursor/global_rules.md"
      KNOWN=0
      ;;
    amp)
      SKILLS_ROOT="$HOME/.amp/skills"
      LAWS_ROOT="$HOME/.amp/global_rules.md"
      KNOWN=0
      ;;
    qwen)
      SKILLS_ROOT="$HOME/.qwen/skills"
      LAWS_ROOT="$HOME/.qwen/global_rules.md"
      KNOWN=0
      ;;
    *)
      SKILLS_ROOT=""
      LAWS_ROOT=""
      KNOWN=0
      ;;
  esac
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
  local tools=(devin claude agy gemini copilot codex opencode goose aider cursor-agent amp qwen)
  printf "\n%-14s %-10s %-8s %-8s %-8s\n" "tool" "installed" "known" "skills" "laws"
  for t in "${tools[@]}"; do
    tool_info "$t"
    local installed="no"
    local skills="no"
    local laws="no"
    local known="no"
    if command -v "$t" &>/dev/null; then
      installed="yes"
    fi
    [[ "$KNOWN" -eq 1 ]] && known="yes"
    if [[ -L "$SKILLS_ROOT" && "$(readlink "$SKILLS_ROOT")" == "$AI_SKILLS" ]]; then
      skills="yes"
    elif [[ -d "$SKILLS_ROOT" && ! -L "$SKILLS_ROOT" ]]; then
      skills="dir"
    fi
    if [[ -L "$LAWS_ROOT" && "$(readlink "$LAWS_ROOT")" == "$GLOBAL_RULES" ]]; then
      laws="yes"
    elif [[ -e "$LAWS_ROOT" && ! -L "$LAWS_ROOT" ]]; then
      laws="file"
    fi
    printf "%-14s %-10s %-8s %-8s %-8s\n" "$t" "$installed" "$known" "$skills" "$laws"
  done
}

cmd_hotwire() {
  local t="$1"
  tool_info "$t"
  log "hotwire $t"
  if [[ "$KNOWN" -ne 1 ]]; then
    log "  $t has no built-in path map. Use: ai-setup.sh hotwire-generic <tool> <skills-path> <laws-path>"
    exit 1
  fi
  if ! command -v "$t" &>/dev/null; then
    log "  $t not installed. Install it first with: ai-setup.sh install $t"
    exit 1
  fi
  link_skills "$SKILLS_ROOT"
  link_laws "$LAWS_ROOT"
  log "  $t hotwired"
}

cmd_hotwire_generic() {
  local t="$1"
  local skills="$2"
  local laws="$3"
  log "hotwire-generic $t"
  if ! command -v "$t" &>/dev/null; then
    log "  $t not installed. Install it first."
    exit 1
  fi
  link_skills "$skills"
  link_laws "$laws"
  log "  $t hotwired"
}

cmd_install() {
  local t="$1"
  local runner="$AI_SKILLS/ai-battle/scripts/battle_runner.sh"
  if [[ ! -x "$runner" ]]; then
    log "ai-battle runner not found at $runner"
    log "clone or pull the repo and try again"
    exit 1
  fi
  log "install menu for $t"
  "$runner" --connect "$t"
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
      [[ $# -lt 1 ]] && { usage; exit 1; }
      cmd_install "$1"
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
