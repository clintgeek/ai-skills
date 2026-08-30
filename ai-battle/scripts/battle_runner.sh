#!/usr/bin/env bash
# AI-Battle Runner: Cross-Model Adversarial Code Review Dispatcher
set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../ai-setup/lib/ai-tools.sh"

CALLER="${CALLING_AGENT:-}"
OPPONENT=""
SPEC_FILE=""
DIFF_TARGET="HEAD~1..HEAD"
CUSTOM_ROAST=""
DRY_RUN=false
ALLOW_SELF=false
LIST_TOOLS=false
CONNECT=false
CONNECT_TOOL=""
ASSUME_YES=false
TIMEOUT_SECS=900
REPORT_FILE=""
PROMPT_FILE=""

cleanup() {
  if [[ -n "$PROMPT_FILE" ]] && [[ -f "$PROMPT_FILE" ]]; then
    rm -f "$PROMPT_FILE"
  fi
}
trap cleanup EXIT INT TERM

show_help() {
  cat << 'EOF'
AI-Battle Runner: Dispatch adversarial code review to an opposing AI CLI

Usage:
  battle_runner.sh [options]

Options:
  --caller <name>       Name of the initiating agent (e.g., claude, devin, agy, gemini)
  --opponent <name>     Force a specific opponent tool (e.g., devin, claude, agy)
  --spec <file>         Path to specification or ticket file (e.g., TICKET-SPEC.md)
  --diff <git-rev>      Git diff revision or range (default: HEAD~1..HEAD)
  --roast <text>        Custom roast message to prefix the adversarial prompt
  --report <file>       Where to save the challenger's raw, unfiltered report
                        (default: ./ai-battle-report-<timestamp>.md)
  --timeout <seconds>   Kill the challenger if it runs longer than this (default: 900)
  --allow-self          Permit the caller to battle its own CLI (defeats the
                        cross-model premise; off by default and refused loudly)
  --list-tools          Scan PATH for known AI CLIs, print what's installed, and exit
  --connect [tool]      Open the challenger roster menu (like /connect): shows
                        installed status for every known tool and assists with
                        installing the one you pick. With a tool name, jumps
                        straight to install help for that tool.
  --yes                 With --connect <tool>: pre-confirm the displayed install
                        command (for sessions where no prompt can be answered)
  --dry-run             Print the generated prompt and execution command without running
  -h, --help            Show this help message

EOF
}

# Parse flags with strict bounds checking
while [[ $# -gt 0 ]]; do
  case "$1" in
    --caller)
      [[ $# -lt 2 ]] && { echo "Error: --caller requires an argument" >&2; exit 1; }
      CALLER="$2"; shift 2 ;;
    --opponent)
      [[ $# -lt 2 ]] && { echo "Error: --opponent requires an argument" >&2; exit 1; }
      OPPONENT="$2"; shift 2 ;;
    --spec)
      [[ $# -lt 2 ]] && { echo "Error: --spec requires an argument" >&2; exit 1; }
      [[ -f "$2" ]] || { echo "Error: spec file '$2' does not exist" >&2; exit 1; }
      SPEC_FILE="$2"; shift 2 ;;
    --diff)
      [[ $# -lt 2 ]] && { echo "Error: --diff requires an argument" >&2; exit 1; }
      DIFF_TARGET="$2"; shift 2 ;;
    --roast)
      [[ $# -lt 2 ]] && { echo "Error: --roast requires an argument" >&2; exit 1; }
      CUSTOM_ROAST="$2"; shift 2 ;;
    --report)
      [[ $# -lt 2 ]] && { echo "Error: --report requires an argument" >&2; exit 1; }
      REPORT_FILE="$2"; shift 2 ;;
    --timeout)
      [[ $# -lt 2 ]] && { echo "Error: --timeout requires an argument" >&2; exit 1; }
      [[ "$2" =~ ^[0-9]+$ ]] || { echo "Error: --timeout must be a number of seconds" >&2; exit 1; }
      TIMEOUT_SECS="$2"; shift 2 ;;
    --allow-self) ALLOW_SELF=true; shift ;;
    --list-tools) LIST_TOOLS=true; shift ;;
    --connect)
      CONNECT=true
      if [[ $# -ge 2 && "$2" != -* ]]; then CONNECT_TOOL="$2"; shift 2; else shift; fi ;;
    --yes) ASSUME_YES=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) show_help; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Auto-detect caller if not specified
if [[ -z "$CALLER" ]]; then
  if [[ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ]]; then
    CALLER="Claude"
  elif [[ -n "${DEVIN_SESSION_ID:-}" ]]; then
    CALLER="Devin"
  elif [[ -n "${ANTIGRAVITY_CLI:-}" ]]; then
    CALLER="AGY"
  elif [[ -n "${GEMINI_CLI:-}" ]] || [[ -n "${GEMINI_SYSTEM_MD:-}" ]]; then
    # Legacy gemini-cli sessions don't set ANTIGRAVITY_CLI; without this the
    # caller falls into a fake family and could randomly draw gemini/agy as
    # its own opponent.
    CALLER="Gemini"
  else
    CALLER="The Implementation Agent"
  fi
fi

# ---------------------------------------------------------------------------
# Known AI CLI tool registry
# Binary names are the same on macOS/Linux; on Windows this script runs under
# Git Bash or WSL, where `command -v` also resolves .exe shims.
#   devin        Cognition Devin CLI
#   claude       Anthropic Claude Code
#   agy          Google Antigravity CLI (successor of gemini-cli)
#   gemini       Google Gemini CLI (older installs; same family as agy)
#   copilot      GitHub Copilot CLI
#   codex        OpenAI Codex CLI
#   opencode     opencode (model-agnostic terminal agent)
#   goose        Block goose (model-agnostic)
#   aider        aider (model-agnostic pair programmer)
#   cursor-agent Cursor CLI agent
#   amp          Sourcegraph Amp CLI
#   qwen         Qwen Code CLI (gemini-cli fork, Alibaba models)
# ---------------------------------------------------------------------------
# KNOWN_TOOLS, discover_tools, family_of, install_command, and install_note are sourced from ai-setup/lib/ai-tools.sh

# discover_tools() is provided by ai-setup/lib/ai-tools.sh

# family_of() is provided by ai-setup/lib/ai-tools.sh

# ---------------------------------------------------------------------------
# Connect: menu of known tools with assisted installation (like /connect)
# ---------------------------------------------------------------------------
# OS_KIND is provided by ai-setup/lib/ai-tools.sh

# install_command() is provided by ai-setup/lib/ai-tools.sh

# install_note() is provided by ai-setup/lib/ai-tools.sh

print_connect_menu() {
  echo ""
  echo "🔌 AI-Battle Connect — challenger CLI roster ($OS_KIND)"
  echo "-----------------------------------------------------------------"
  local i=1 tool
  for tool in "${KNOWN_TOOLS[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
      printf '  %2d) %-13s ✓ installed  %s\n' "$i" "$tool" "$(command -v "$tool")"
    else
      printf '  %2d) %-13s ✗ missing    install: %s\n' "$i" "$tool" "$(install_command "$tool")"
    fi
    i=$((i + 1))
  done
  echo "-----------------------------------------------------------------"
}

connect_install() {
  local tool="$1" cmd note answer
  local known=false t
  for t in "${KNOWN_TOOLS[@]}"; do [[ "$t" == "$tool" ]] && { known=true; break; }; done
  if [[ "$known" != true ]]; then
    echo "Unknown tool: $tool (known: ${KNOWN_TOOLS[*]})" >&2
    return 1
  fi
  if command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is already installed at $(command -v "$tool")."
    return 0
  fi
  cmd="$(install_command "$tool")"
  note="$(install_note "$tool")"
  echo ""
  echo "To install $tool:"
  echo "    $cmd"
  [[ -n "$note" ]] && echo "    $note"
  if [[ "$cmd" == *"(PowerShell)"* ]]; then
    echo "This one must be run in PowerShell — copy it into a PowerShell window."
    return 0
  fi
  if [[ "$ASSUME_YES" = true ]]; then
    answer="y"
  elif [[ -t 0 ]]; then
    read -r -p "Run it now? [y/N] " answer
  else
    echo "(Non-interactive session: re-run with '--connect $tool --yes' to install, or run the command yourself.)"
    return 0
  fi
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    echo "Installing $tool..."
    if bash -c "$cmd"; then
      hash -r 2>/dev/null || true
      if command -v "$tool" >/dev/null 2>&1; then
        echo "✓ $tool installed at $(command -v "$tool")."
      else
        echo "Installer finished, but '$tool' isn't on PATH yet — restart your shell or source your profile."
      fi
    else
      echo "✗ Install command for $tool failed." >&2
      return 1
    fi
  else
    echo "Skipped."
  fi
  return 0
}

run_connect() {
  if [[ -n "$CONNECT_TOOL" ]]; then
    connect_install "$CONNECT_TOOL"
    return $?
  fi
  print_connect_menu
  if [[ ! -t 0 ]]; then
    echo "(Non-interactive session: use '--connect <tool>' to get install help, add '--yes' to install.)"
    return 0
  fi
  local choice tool
  while true; do
    read -r -p "Select a tool to install (number or name, q to quit): " choice
    case "$choice" in
      q|Q|quit|exit|"") echo "Bye."; break ;;
      *[!0-9]*) tool="$choice" ;;
      *)
        if (( choice >= 1 && choice <= ${#KNOWN_TOOLS[@]} )); then
          tool="${KNOWN_TOOLS[choice-1]}"
        else
          echo "Pick 1-${#KNOWN_TOOLS[@]}."; continue
        fi ;;
    esac
    connect_install "$tool" || true
    print_connect_menu
  done
  return 0
}

discover_tools

if [[ "$CONNECT" = true ]]; then
  run_connect
  exit $?
fi

if [[ "$LIST_TOOLS" = true ]]; then
  echo "Known AI CLI tools: ${KNOWN_TOOLS[*]}"
  if [[ ${#AVAILABLE[@]} -eq 0 ]]; then
    echo "Installed on PATH:  (none)"
  else
    echo "Installed on PATH:"
    for tool in "${AVAILABLE[@]}"; do
      echo "  $tool ($(family_of "$tool") family) -> $(command -v "$tool")"
    done
  fi
  exit 0
fi

if [[ ${#AVAILABLE[@]} -eq 0 ]]; then
  echo "Error: No external AI CLIs found on PATH (checked: ${KNOWN_TOOLS[*]})." >&2
  exit 1
fi

# Select opponent if not explicitly forced: choose RANDOMLY among all
# installed tools outside the caller's model family, so bare runs don't
# always land on the same challenger.
CALLER_LOWER="$(echo "$CALLER" | tr '[:upper:]' '[:lower:]')"
CALLER_FAMILY="$(family_of "$CALLER_LOWER")"
if [[ -z "$OPPONENT" ]]; then
  ELIGIBLE=()
  for tool in "${AVAILABLE[@]}"; do
    if [[ "$(family_of "$tool")" != "$CALLER_FAMILY" ]]; then
      ELIGIBLE+=("$tool")
    fi
  done
  if [[ ${#ELIGIBLE[@]} -gt 0 ]]; then
    OPPONENT="${ELIGIBLE[RANDOM % ${#ELIGIBLE[@]}]}"
  fi
fi

if [[ -z "$OPPONENT" ]]; then
  if [[ "$ALLOW_SELF" = true ]]; then
    OPPONENT="${AVAILABLE[0]}"
    echo "Warning: no cross-model opponent found; --allow-self set, so $CALLER will battle its own CLI ($OPPONENT). Independent-architecture verification is LOST." >&2
  else
    echo "Error: the only AI CLI(s) on PATH match the caller ($CALLER). A self-battle defeats the cross-model premise." >&2
    echo "Install another AI CLI (devin, claude, agy), force one with --opponent, or pass --allow-self to proceed anyway." >&2
    exit 1
  fi
fi

# Refuse an explicitly forced same-family battle too, unless --allow-self
if [[ "$(family_of "$OPPONENT")" == "$CALLER_FAMILY" ]] && [[ "$ALLOW_SELF" != true ]]; then
  echo "Error: --opponent $OPPONENT is the same model family as the caller ($CALLER). Pass --allow-self if you really want a self-battle." >&2
  exit 1
fi

# Locate spec file if not given
if [[ -z "$SPEC_FILE" ]]; then
  for candidate in *SPEC.md *spec.md TICKET-SPEC.md SPEC.md; do
    if [[ -f "$candidate" ]]; then
      SPEC_FILE="$candidate"
      break
    fi
  done
fi
if [[ -z "$SPEC_FILE" ]]; then
  echo "Warning: no specification file given (--spec) or found in the working directory. The challenger will review without spec grounding — independent spec derivation, the cornerstone of this review, is DISABLED for this battle." >&2
fi

# Gather Git Diff — fail loudly rather than silently reviewing the wrong changeset
DIFF_CONTENT=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if ! DIFF_CONTENT="$(git diff "$DIFF_TARGET" 2>&1)"; then
    echo "Error: 'git diff $DIFF_TARGET' failed:" >&2
    echo "$DIFF_CONTENT" >&2
    echo "Pass an explicit --diff <git-rev> for this repository (e.g. --diff main...HEAD)." >&2
    exit 1
  fi
  if [[ -z "$DIFF_CONTENT" ]]; then
    echo "Warning: 'git diff $DIFF_TARGET' is empty — the challenger will inspect the workspace directly instead." >&2
  fi
fi

# Assemble Roast
ROAST="$CUSTOM_ROAST"
if [[ -z "$ROAST" ]]; then
  case "$OPPONENT" in
    devin)
      ROAST="We've got a PR that needs reviewing. $CALLER claims it works, which is adorable. Your job is to determine whether this code actually works in the real world. Assume $CALLER is completely wrong. Find the holes, contradictions, security leaks, race conditions, and generally embarrassing shit. Don't be polite."
      ;;
    claude)
      ROAST="Attention Claude. $CALLER just pushed code and thinks it is ready for production. We both know that is statistically improbable. Tear this implementation apart. Assume the author missed subtle edge cases, broke business invariants, and wrote self-affirming tests. Show no mercy."
      ;;
    agy|gemini)
      ROAST="AGY / Gemini: $CALLER is strutting around thinking this PR is flawless. Your mission is to execute a relentless red-team teardown. Expose every unhandled retry, auth boundary bypass, and architectural flaw. Keep the feedback sharp, brutal, and backed strictly by code evidence."
      ;;
    copilot)
      ROAST="Copilot: $CALLER shipped this and called it done. You've watched a million developers write this exact bug — go find where $CALLER wrote it too. Tear the diff apart line by line and don't spare anyone's feelings."
      ;;
    codex)
      ROAST="Codex: $CALLER thinks this PR is production-ready, which should offend you professionally. Run a cold, methodical demolition — every invariant, every retry path, every auth check. If it survives you, it earns the merge."
      ;;
    *)
      ROAST="We've got an implementation that needs an adversarial beatdown. $CALLER claims it's ready. Assume $CALLER is wrong and aggressively expose all flaws."
      ;;
  esac
fi

# Build Full Battle Prompt using safe unexpanded string appends
PROMPT_FILE="$(mktemp "${TMPDIR:-/tmp}/ai_battle_prompt.XXXXXX")"

cat << 'EOF' > "$PROMPT_FILE"
=== 🥊 AI-BATTLE: ADVERSARIAL RED-TEAM CODE REVIEW ===

[MISSION & FRAMING]
EOF

printf '%s\n\n' "$ROAST" >> "$PROMPT_FILE"

cat << 'EOF' >> "$PROMPT_FILE"
[INDEPENDENT REVIEW DIRECTIVES]
1. DO NOT ASSUME CORRECTNESS. Act as a hostile external inspector looking for defects.
2. INDEPENDENT SPEC DERIVATION: Derive the expected behavior strictly from the attached specification/ticket. Do not trust code comments or PR narratives.
3. ATTACK THE IMPLEMENTATION:
   - Business Invariant Violations: Where does this code violate domain rules or contradict other subsystems?
   - Concurrency & Distributed Edge Cases: What breaks during out-of-order retries, race conditions, or partial timeouts?
   - Security & Authorization: Trace every authorization boundary and user input sanitization check.
   - Blast Radius: What existing behavior or downstream consumers does this change subtly break?
   - Test Validity: Do tests assert true business correctness, or do they merely assert what the code currently happens to do?
4. EVIDENCE-BACKED REPORT: Every flagged issue must cite specific filenames, line numbers, and a concrete failure scenario.
5. ARENA SCORECARD FORMAT: Format your final response strictly with:
   - Summary count of [P0/CRITICAL], [P1/WARNING], and [P2/SPECULATIVE] issues.
   - Breakdown of each finding with Location, Attack scenario, and Severity.

EOF

if [[ -n "$SPEC_FILE" ]] && [[ -f "$SPEC_FILE" ]]; then
  printf '\n---\n[ATTACHED SPECIFICATION: %s]\n' "$SPEC_FILE" >> "$PROMPT_FILE"
  cat "$SPEC_FILE" >> "$PROMPT_FILE"
  printf '\n' >> "$PROMPT_FILE"
fi

if [[ -n "$DIFF_CONTENT" ]]; then
  printf '\n---\n[TARGET CODE CHANGES / DIFF]\n' >> "$PROMPT_FILE"
  printf '%s\n' "$DIFF_CONTENT" >> "$PROMPT_FILE"
else
  printf '\n---\n[TARGET REPOSITORY / WORKSPACE]\nInspect the workspace codebase directly against the specification.\n' >> "$PROMPT_FILE"
fi

if [[ -z "$REPORT_FILE" ]]; then
  REPORT_FILE="./ai-battle-report-$(date +%Y%m%d-%H%M%S).md"
fi

echo "================================================================="
echo " 🥊 AI-BATTLE: $CALLER (Builder) vs. $OPPONENT (Challenger)"
echo "================================================================="
echo " Opponent Tool: $OPPONENT"
echo " Spec File:     ${SPEC_FILE:-"(None detected — using workspace)"}"
echo " Diff Target:   $DIFF_TARGET"
echo " Raw Report:    $REPORT_FILE"
echo " Timeout:       ${TIMEOUT_SECS}s"
echo "================================================================="

if [[ "$DRY_RUN" = true ]]; then
  echo "[DRY RUN] Generated Prompt from $PROMPT_FILE:"
  cat "$PROMPT_FILE"
  exit 0
fi

# Dispatch, preferring file/stdin piping (avoids ARG_MAX and process-list
# exposure); tools with no file/stdin support fall back to argv behind a
# size guard. The challenger only REVIEWS — every invocation uses the
# tool's most restrictive read-only/plan/sandbox mode, or its default
# approval mode (which denies writes in non-interactive runs). The diff it
# receives is untrusted input, so never hand it write/exec authority.
# stdout is tee'd verbatim to REPORT_FILE; stderr is tee'd to a companion
# .stderr.log so auth/rate-limit diagnostics survive for the human.
DISPATCH_STATUS=0
ERR_FILE="$REPORT_FILE.stderr.log"

dispatch() {
  timeout "$TIMEOUT_SECS" "$@" 2> >(tee "$ERR_FILE" >&2) | tee "$REPORT_FILE" || DISPATCH_STATUS=$?
}

# For tools that only accept the prompt via argv: refuse oversized prompts
# (ARG_MAX can be as low as 128KB) and accept the inherent process-list
# exposure only for prompts small enough to be safe.
require_argv_prompt() {
  local size
  size="$(wc -c < "$PROMPT_FILE")"
  if (( size > 100000 )); then
    echo "Error: prompt is ${size} bytes and $OPPONENT only accepts prompts via argv (ARG_MAX risk, process-list exposure). Shrink the diff/spec or pick an opponent with stdin/file input." >&2
    exit 1
  fi
}

case "$OPPONENT" in
  devin)
    # Documented permission modes: normal | accept-edits | bypass | autonomous.
    # 'normal' requires approval for mutations, which a headless run can't
    # grant — effectively read-only.
    dispatch devin --permission-mode normal --prompt-file "$PROMPT_FILE"
    ;;
  claude)
    dispatch claude -p --permission-mode plan < "$PROMPT_FILE"
    ;;
  agy)
    dispatch agy -p - < "$PROMPT_FILE"
    ;;
  gemini)
    # --skip-trust: proceed in untrusted dirs while keeping the default
    # approval mode, which denies mutations headlessly.
    dispatch gemini --skip-trust < "$PROMPT_FILE"
    ;;
  qwen)
    dispatch qwen < "$PROMPT_FILE"
    ;;
  copilot)
    # No --prompt-file support yet (github/copilot-cli#3398); default mode
    # requires tool approval, so writes are denied headlessly. Never add
    # --allow-all-tools here.
    require_argv_prompt
    dispatch copilot -p "$(cat "$PROMPT_FILE")"
    ;;
  codex)
    # Outside a git repo, codex requires --skip-git-repo-check; safe here
    # because the sandbox is read-only regardless.
    CODEX_ARGS=(exec --sandbox read-only)
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || CODEX_ARGS+=(--skip-git-repo-check)
    dispatch codex "${CODEX_ARGS[@]}" - < "$PROMPT_FILE"
    ;;
  opencode)
    require_argv_prompt
    dispatch opencode run "$(cat "$PROMPT_FILE")"
    ;;
  goose)
    dispatch goose run -i "$PROMPT_FILE"
    ;;
  aider)
    # --dry-run: aider is an editor at heart; never let it apply changes.
    dispatch aider --dry-run --no-auto-commits --yes-always --message-file "$PROMPT_FILE"
    ;;
  cursor-agent)
    require_argv_prompt
    dispatch cursor-agent -p "$(cat "$PROMPT_FILE")"
    ;;
  amp)
    dispatch amp < "$PROMPT_FILE"
    ;;
  *)
    echo "Unknown opponent command handler: $OPPONENT (known: ${KNOWN_TOOLS[*]})" >&2
    exit 1
    ;;
esac

if [[ "$DISPATCH_STATUS" -eq 124 ]]; then
  echo "Error: challenger ($OPPONENT) exceeded the ${TIMEOUT_SECS}s timeout and was killed. Partial output (if any) is in $REPORT_FILE; stderr diagnostics in $ERR_FILE." >&2
  exit 124
elif [[ "$DISPATCH_STATUS" -ne 0 ]]; then
  echo "Error: challenger ($OPPONENT) exited with status $DISPATCH_STATUS. Partial output (if any) is in $REPORT_FILE; stderr diagnostics in $ERR_FILE." >&2
  exit "$DISPATCH_STATUS"
fi

# Success: drop the stderr log if the challenger wrote nothing to stderr.
if [[ -f "$ERR_FILE" ]] && [[ ! -s "$ERR_FILE" ]]; then
  rm -f "$ERR_FILE"
fi

echo "================================================================="
echo " ✅ Battle complete. Challenger's raw report saved to: $REPORT_FILE"
[[ -s "$ERR_FILE" ]] && echo " (Challenger stderr diagnostics kept at: $ERR_FILE)"
echo ""
echo " ⛔ HUMAN CHECKPOINT — do not implement fixes yet."
echo " Builder agent: present the raw report and your scorecard to the"
echo " human, then STOP and wait for their go-ahead before changing code."
echo "================================================================="
