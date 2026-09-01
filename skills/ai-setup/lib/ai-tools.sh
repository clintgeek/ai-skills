#!/usr/bin/env bash
# Shared AI CLI tool registry for ai-setup and ai-battle.
# Source this file; do not execute it directly.
#
# Requires associative arrays: bash 4+ or zsh. macOS ships bash 3.2 as
# /bin/bash, so a caller that reaches this file through a bare `bash` on a
# stock Mac lands here -- say so plainly rather than emitting a wall of
# "declare: -A: invalid option" and exiting 2.
if [ -n "${BASH_VERSION:-}" ] && [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "ai-tools.sh: needs bash 4+ or zsh for associative arrays; found bash $BASH_VERSION." >&2
  echo "  macOS ships bash 3.2 as /bin/bash. Install a newer one (brew install bash)" >&2
  echo "  and make sure its directory precedes /bin on PATH." >&2
  return 1 2>/dev/null || exit 1
fi

OS_KIND="linux"
case "$(uname -s)" in
  Darwin) OS_KIND="mac" ;;
  Linux) OS_KIND="linux" ;;
  MINGW*|MSYS*|CYGWIN*) OS_KIND="windows" ;;
esac

# The tools this repo actually tracks. Trimmed from eleven on 2026-09-01: five
# of the originals were neither installed nor path-verified, and their entries
# were frozen guesses -- install commands that go stale and skills/laws paths
# `hotwire` refuses to use anyway (TOOL_KNOWN=0 sends you to hotwire-generic).
#
# Dropped: goose, aider, cursor-agent, amp, qwen. Nothing is lost by dropping a
# tool from here: hotwire-generic wires anything with explicit paths, and an
# install command is a lookup rather than something worth freezing in a file.
#
# List of tool binary names in the battle/setup registry.
AI_TOOLS=(devin claude agy copilot codex opencode)

# Backwards-compatible alias for ai-battle.
KNOWN_TOOLS=("${AI_TOOLS[@]}")

declare -A TOOL_NAME
TOOL_NAME[devin]="Cognition Devin CLI"
TOOL_NAME[claude]="Anthropic Claude Code"
TOOL_NAME[agy]="Google Antigravity CLI"
TOOL_NAME[copilot]="GitHub Copilot CLI"
TOOL_NAME[codex]="OpenAI Codex CLI"
TOOL_NAME[opencode]="opencode"

declare -A TOOL_FAMILY
TOOL_FAMILY[devin]="cognition"
TOOL_FAMILY[claude]="anthropic"
TOOL_FAMILY[agy]="google"
TOOL_FAMILY[copilot]="github"
TOOL_FAMILY[codex]="openai"
TOOL_FAMILY[opencode]="opencode"

declare -A TOOL_INSTALL_LINUX
TOOL_INSTALL_LINUX[devin]='curl -fsSL https://cli.devin.ai/install.sh | bash'
TOOL_INSTALL_LINUX[claude]='curl -fsSL https://claude.ai/install.sh | bash'
TOOL_INSTALL_LINUX[agy]='curl -fsSL https://antigravity.google/cli/install.sh | bash'
TOOL_INSTALL_LINUX[copilot]='npm install -g @github/copilot'
TOOL_INSTALL_LINUX[codex]='npm install -g @openai/codex'
TOOL_INSTALL_LINUX[opencode]='curl -fsSL https://opencode.ai/install | bash'

declare -A TOOL_INSTALL_MAC
TOOL_INSTALL_MAC[devin]='curl -fsSL https://cli.devin.ai/install.sh | bash'
TOOL_INSTALL_MAC[claude]='curl -fsSL https://claude.ai/install.sh | bash'
TOOL_INSTALL_MAC[agy]='curl -fsSL https://antigravity.google/cli/install.sh | bash'
TOOL_INSTALL_MAC[copilot]='npm install -g @github/copilot'
TOOL_INSTALL_MAC[codex]='npm install -g @openai/codex'
TOOL_INSTALL_MAC[opencode]='curl -fsSL https://opencode.ai/install | bash'

declare -A TOOL_INSTALL_WINDOWS
TOOL_INSTALL_WINDOWS[devin]='irm https://static.devin.ai/cli/setup.ps1 | iex  (PowerShell)'
TOOL_INSTALL_WINDOWS[claude]='irm https://claude.ai/install.ps1 | iex  (PowerShell)'
TOOL_INSTALL_WINDOWS[agy]='irm https://antigravity.google/cli/install.ps1 | iex  (PowerShell)'
TOOL_INSTALL_WINDOWS[copilot]='npm install -g @github/copilot'
TOOL_INSTALL_WINDOWS[codex]='npm install -g @openai/codex'
TOOL_INSTALL_WINDOWS[opencode]='curl -fsSL https://opencode.ai/install | bash'

declare -A TOOL_INSTALL_NOTE
TOOL_INSTALL_NOTE[codex]="Alternative: brew install codex"
TOOL_INSTALL_NOTE[claude]="Alternative: npm install -g @anthropic-ai/claude-code"
TOOL_INSTALL_NOTE[opencode]="Alternative: npm install -g opencode-ai"

# Global skill and laws paths.
#
# TOOL_KNOWN=1 means the path is VETTED -- someone confirmed the tool actually
# reads it, not merely that a symlink there resolves. opencode was promoted on
# 2026-09-01 after it enumerated all five skills by name from ~/.opencode/skills.
# TOOL_KNOWN=0 means the path is a plausible guess; `hotwire` refuses it and
# `hotwire-generic <tool> <skills> <laws>` is the route until someone verifies.
declare -A TOOL_SKILLS
TOOL_SKILLS[devin]="$HOME/.config/devin/skills"
TOOL_SKILLS[claude]="$HOME/.claude/skills"
TOOL_SKILLS[agy]="$HOME/.antigravity/skills"
TOOL_SKILLS[copilot]="$HOME/.copilot/skills"
TOOL_SKILLS[codex]="$HOME/.codex/skills"
TOOL_SKILLS[opencode]="$HOME/.opencode/skills"

declare -A TOOL_LAWS
TOOL_LAWS[devin]="$HOME/.config/devin/global_rules.md"
TOOL_LAWS[claude]="$HOME/.claude/CLAUDE.md"
TOOL_LAWS[agy]="$HOME/.antigravity/global_rules.md"
TOOL_LAWS[copilot]="$HOME/.copilot/copilot-instructions.md"
TOOL_LAWS[codex]="$HOME/.codex/global_rules.md"
TOOL_LAWS[opencode]="$HOME/.opencode/global_rules.md"

declare -A TOOL_KNOWN
TOOL_KNOWN[devin]=1
TOOL_KNOWN[claude]=1
TOOL_KNOWN[copilot]=1
TOOL_KNOWN[agy]=1
TOOL_KNOWN[codex]=0
TOOL_KNOWN[opencode]=1

# Tool metadata helpers (same names as the originals in ai-battle for easy sourcing).

tool_display_name() { echo "${TOOL_NAME[$1]:-$1}"; }

family_of() { echo "${TOOL_FAMILY[$1]:-$1}"; }

install_command() {
  local tool="$1"
  local cmd=""
  case "$OS_KIND" in
    mac)  cmd="${TOOL_INSTALL_MAC[$tool]:-}"; [[ -z "$cmd" ]] && cmd="${TOOL_INSTALL_LINUX[$tool]:-}" ;;
    windows) cmd="${TOOL_INSTALL_WINDOWS[$tool]:-}"; [[ -z "$cmd" ]] && cmd="${TOOL_INSTALL_LINUX[$tool]:-}" ;;
    *)    cmd="${TOOL_INSTALL_LINUX[$tool]:-}" ;;
  esac
  echo "$cmd"
}

install_note() { echo "${TOOL_INSTALL_NOTE[$1]:-}"; }

discover_tools() {
  AI_TOOLS_AVAILABLE=()
  AVAILABLE=()
  local tool
  for tool in "${AI_TOOLS[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
      AI_TOOLS_AVAILABLE+=("$tool")
      AVAILABLE+=("$tool")
    fi
  done
  return 0
}

# ---------------------------------------------------------------------------
# Tool roster and selection (used by `ai-setup select`)
# ---------------------------------------------------------------------------
# One implementation, because two would drift. NOTE this file is sourced by both
# bash and zsh, and their arrays index differently (bash 0-based, zsh 1-based),
# so nothing here indexes an array -- selections are resolved by iterating with
# a counter instead.

# Numbered roster with installed status.
tool_roster() {
  echo ""
  echo "AI CLI roster (${OS_KIND})"
  echo "-----------------------------------------------------------------"
  local i=0 tool
  for tool in "${AI_TOOLS[@]}"; do
    i=$((i + 1))
    if command -v "$tool" >/dev/null 2>&1; then
      printf '  %2d) %-13s [installed]  %s\n' "$i" "$tool" "$(command -v "$tool")"
    else
      printf '  %2d) %-13s [missing]    %s\n' "$i" "$tool" "$(install_command "$tool")"
    fi
  done
  echo "-----------------------------------------------------------------"
}

# Resolve free-form selection input into tool names, one per line.
# Accepts numbers and/or names, comma and/or space separated, plus "all".
# Unknown tokens are reported on stderr and skipped, never silently dropped.
resolve_tool_selection() {
  local raw="$1"
  [[ -z "$raw" ]] && return 0
  if [[ "$raw" == "all" ]]; then
    printf '%s\n' "${AI_TOOLS[@]}"
    return 0
  fi
  local tok i tool matched seen=""
  # Normalize separators to spaces without needing an array index.
  for tok in $(echo "$raw" | tr ',' ' '); do
    [[ -z "$tok" ]] && continue
    matched=""
    case "$tok" in
      ''|*[!0-9]*)
        # A name.
        for tool in "${AI_TOOLS[@]}"; do
          [[ "$tool" == "$tok" ]] && { matched="$tool"; break; }
        done ;;
      *)
        # A position in the roster.
        i=0
        for tool in "${AI_TOOLS[@]}"; do
          i=$((i + 1))
          [[ "$i" -eq "$tok" ]] && { matched="$tool"; break; }
        done ;;
    esac
    if [[ -n "$matched" ]]; then
      # Dedupe: selecting both "2" and "claude" must not install it twice.
      case " $seen " in
        *" $matched "*) ;;
        *) seen="$seen $matched"; echo "$matched" ;;
      esac
    else
      echo "  ignoring unrecognized selection: $tok" >&2
    fi
  done
  return 0
}

# Install one tool, printing the command first. Returns 0 if it ends up present.
# assume_yes=true installs without prompting; otherwise a TTY is asked and a
# non-interactive session refuses (never install a vendor script unprompted).
tool_install_one() {
  local tool="$1" assume_yes="${2:-false}"
  local cmd note answer
  if command -v "$tool" >/dev/null 2>&1; then
    echo "  $tool already installed at $(command -v "$tool")"
    return 0
  fi
  cmd="$(install_command "$tool")"
  note="$(install_note "$tool")"
  if [[ -z "$cmd" ]]; then
    echo "  no install command known for $tool" >&2
    return 1
  fi
  echo ""
  echo "  $tool:"
  echo "    $cmd"
  [[ -n "$note" ]] && echo "    $note"
  if [[ "$cmd" == *"(PowerShell)"* ]]; then
    echo "    (PowerShell only -- run this yourself in a PowerShell window)"
    return 1
  fi
  if [[ "$assume_yes" != true ]]; then
    if [[ -t 0 ]]; then
      read -r -p "    Run it? [y/N] " answer
      [[ "$answer" =~ ^[Yy]$ ]] || { echo "    skipped."; return 1; }
    else
      echo "    non-interactive and not pre-confirmed; skipped." >&2
      return 1
    fi
  fi
  echo "    installing $tool..."
  if bash -c "$cmd"; then
    hash -r 2>/dev/null || true
    if command -v "$tool" >/dev/null 2>&1; then
      echo "    $tool installed at $(command -v "$tool")"
      return 0
    fi
    echo "    installer finished but $tool is not on PATH yet -- restart your shell" >&2
    return 1
  fi
  echo "    install failed for $tool" >&2
  return 1
}
