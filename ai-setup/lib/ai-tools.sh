#!/usr/bin/env bash
# Shared AI CLI tool registry for ai-setup and ai-battle.
# Source this file; do not execute it directly.

OS_KIND="linux"
case "$(uname -s)" in
  Darwin) OS_KIND="mac" ;;
  Linux) OS_KIND="linux" ;;
  MINGW*|MSYS*|CYGWIN*) OS_KIND="windows" ;;
esac

# List of tool binary names in the battle/setup registry.
AI_TOOLS=(devin claude agy copilot codex opencode goose aider cursor-agent amp qwen)

# Backwards-compatible alias for ai-battle.
KNOWN_TOOLS=("${AI_TOOLS[@]}")

declare -A TOOL_NAME
TOOL_NAME[devin]="Cognition Devin CLI"
TOOL_NAME[claude]="Anthropic Claude Code"
TOOL_NAME[agy]="Google Antigravity CLI"
TOOL_NAME[copilot]="GitHub Copilot CLI"
TOOL_NAME[codex]="OpenAI Codex CLI"
TOOL_NAME[opencode]="opencode"
TOOL_NAME[goose]="Block goose"
TOOL_NAME[aider]="aider"
TOOL_NAME[cursor-agent]="Cursor CLI agent"
TOOL_NAME[amp]="Sourcegraph Amp CLI"
TOOL_NAME[qwen]="Qwen Code CLI"

declare -A TOOL_FAMILY
TOOL_FAMILY[devin]="cognition"
TOOL_FAMILY[claude]="anthropic"
TOOL_FAMILY[agy]="google"
TOOL_FAMILY[copilot]="github"
TOOL_FAMILY[codex]="openai"
TOOL_FAMILY[opencode]="opencode"
TOOL_FAMILY[goose]="goose"
TOOL_FAMILY[aider]="aider"
TOOL_FAMILY[cursor-agent]="cursor"
TOOL_FAMILY[amp]="sourcegraph"
TOOL_FAMILY[qwen]="alibaba"

declare -A TOOL_INSTALL_LINUX
TOOL_INSTALL_LINUX[devin]='curl -fsSL https://cli.devin.ai/install.sh | bash'
TOOL_INSTALL_LINUX[claude]='curl -fsSL https://claude.ai/install.sh | bash'
TOOL_INSTALL_LINUX[agy]='curl -fsSL https://antigravity.google/cli/install.sh | bash'
TOOL_INSTALL_LINUX[copilot]='npm install -g @github/copilot'
TOOL_INSTALL_LINUX[codex]='npm install -g @openai/codex'
TOOL_INSTALL_LINUX[opencode]='curl -fsSL https://opencode.ai/install | bash'
TOOL_INSTALL_LINUX[goose]='curl -fsSL https://github.com/block/goose/releases/download/stable/download_cli.sh | bash'
TOOL_INSTALL_LINUX[aider]='python -m pip install aider-install && aider-install'
TOOL_INSTALL_LINUX[cursor-agent]='curl https://cursor.com/install -fsS | bash'
TOOL_INSTALL_LINUX[amp]='npm install -g @sourcegraph/amp'
TOOL_INSTALL_LINUX[qwen]='npm install -g @qwen-code/qwen-code'

declare -A TOOL_INSTALL_MAC
TOOL_INSTALL_MAC[devin]='curl -fsSL https://cli.devin.ai/install.sh | bash'
TOOL_INSTALL_MAC[claude]='curl -fsSL https://claude.ai/install.sh | bash'
TOOL_INSTALL_MAC[agy]='curl -fsSL https://antigravity.google/cli/install.sh | bash'
TOOL_INSTALL_MAC[copilot]='npm install -g @github/copilot'
TOOL_INSTALL_MAC[codex]='npm install -g @openai/codex'
TOOL_INSTALL_MAC[opencode]='curl -fsSL https://opencode.ai/install | bash'
TOOL_INSTALL_MAC[goose]='curl -fsSL https://github.com/block/goose/releases/download/stable/download_cli.sh | bash'
TOOL_INSTALL_MAC[aider]='python -m pip install aider-install && aider-install'
TOOL_INSTALL_MAC[cursor-agent]='curl https://cursor.com/install -fsS | bash'
TOOL_INSTALL_MAC[amp]='npm install -g @sourcegraph/amp'
TOOL_INSTALL_MAC[qwen]='npm install -g @qwen-code/qwen-code'

declare -A TOOL_INSTALL_WINDOWS
TOOL_INSTALL_WINDOWS[devin]='irm https://static.devin.ai/cli/setup.ps1 | iex  (PowerShell)'
TOOL_INSTALL_WINDOWS[claude]='irm https://claude.ai/install.ps1 | iex  (PowerShell)'
TOOL_INSTALL_WINDOWS[agy]='irm https://antigravity.google/cli/install.ps1 | iex  (PowerShell)'
TOOL_INSTALL_WINDOWS[copilot]='npm install -g @github/copilot'
TOOL_INSTALL_WINDOWS[codex]='npm install -g @openai/codex'
TOOL_INSTALL_WINDOWS[opencode]='curl -fsSL https://opencode.ai/install | bash'
TOOL_INSTALL_WINDOWS[goose]='curl -fsSL https://github.com/block/goose/releases/download/stable/download_cli.sh | bash'
TOOL_INSTALL_WINDOWS[aider]='python -m pip install aider-install && aider-install'
TOOL_INSTALL_WINDOWS[cursor-agent]='curl https://cursor.com/install -fsS | bash'
TOOL_INSTALL_WINDOWS[amp]='npm install -g @sourcegraph/amp'
TOOL_INSTALL_WINDOWS[qwen]='npm install -g @qwen-code/qwen-code'

declare -A TOOL_INSTALL_NOTE
TOOL_INSTALL_NOTE[codex]="Alternative: brew install codex"
TOOL_INSTALL_NOTE[claude]="Alternative: npm install -g @anthropic-ai/claude-code"
TOOL_INSTALL_NOTE[opencode]="Alternative: npm install -g opencode-ai"

# Best-guess global skill and laws paths. Known entries are vetted; others are stubs.
declare -A TOOL_SKILLS
TOOL_SKILLS[devin]="$HOME/.config/devin/skills"
TOOL_SKILLS[claude]="$HOME/.claude/skills"
TOOL_SKILLS[agy]="$HOME/.antigravity/skills"
TOOL_SKILLS[copilot]="$HOME/.copilot/skills"
TOOL_SKILLS[codex]="$HOME/.codex/skills"
TOOL_SKILLS[opencode]="$HOME/.opencode/skills"
TOOL_SKILLS[goose]="$HOME/.goose/skills"
TOOL_SKILLS[aider]="$HOME/.aider/skills"
TOOL_SKILLS[cursor-agent]="$HOME/.cursor/skills"
TOOL_SKILLS[amp]="$HOME/.amp/skills"
TOOL_SKILLS[qwen]="$HOME/.qwen/skills"

declare -A TOOL_LAWS
TOOL_LAWS[devin]="$HOME/.config/devin/global_rules.md"
TOOL_LAWS[claude]="$HOME/.claude/CLAUDE.md"
TOOL_LAWS[agy]="$HOME/.antigravity/global_rules.md"
TOOL_LAWS[copilot]="$HOME/.copilot/copilot-instructions.md"
TOOL_LAWS[codex]="$HOME/.codex/global_rules.md"
TOOL_LAWS[opencode]="$HOME/.opencode/global_rules.md"
TOOL_LAWS[goose]="$HOME/.goose/global_rules.md"
TOOL_LAWS[aider]="$HOME/.aider/global_rules.md"
TOOL_LAWS[cursor-agent]="$HOME/.cursor/global_rules.md"
TOOL_LAWS[amp]="$HOME/.amp/global_rules.md"
TOOL_LAWS[qwen]="$HOME/.qwen/global_rules.md"

declare -A TOOL_KNOWN
TOOL_KNOWN[devin]=1
TOOL_KNOWN[claude]=1
TOOL_KNOWN[copilot]=1
TOOL_KNOWN[agy]=1
TOOL_KNOWN[codex]=0
TOOL_KNOWN[opencode]=0
TOOL_KNOWN[goose]=0
TOOL_KNOWN[aider]=0
TOOL_KNOWN[cursor-agent]=0
TOOL_KNOWN[amp]=0
TOOL_KNOWN[qwen]=0

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
