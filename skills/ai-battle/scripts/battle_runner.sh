#!/usr/bin/env bash
# AI-Battle Runner: Cross-Model Adversarial Code Review Dispatcher
set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../ai-setup/lib/ai-tools.sh"
source "$SCRIPT_DIR/../../../lib/spec_builder.sh"
source "$SCRIPT_DIR/../../../lib/report-check.sh"
source "$SCRIPT_DIR/../../../lib/fs-helpers.sh"

# Never as root. Lower stakes than the other entry points -- this writes reports
# to the working directory rather than reconfiguring $HOME -- but root-owned
# files scattered through the repo are a real nuisance, and "never as root" is
# the policy for the tool, not for two thirds of it.
refuse_if_root || exit 1

CALLER="${CALLING_AGENT:-}"
OPPONENT=""
SPEC_FILE=""
NO_SPEC=false
DIFF_TARGET="HEAD~1..HEAD"
CUSTOM_ROAST=""
DRY_RUN=false
ALLOW_SELF=false
LIST_TOOLS=false
# Consumed by the sh wrapper for BOOTSTRAP consent (installing a bash 4+), not
# by the battle itself. Accepted here so `ai-battle --yes` is not an error.
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
  --caller <name>       Name of the initiating agent (e.g., claude, devin, agy)
  --opponent <name>     Force a specific opponent tool (e.g., devin, claude, agy)
  --spec <file>         Path to specification or ticket file (e.g., TICKET-SPEC.md).
                        If omitted and none is found in the working directory, a
                        DRAFT TICKET-SPEC.md is scaffolded (via lib/spec_builder.sh)
                        and the battle stops (exit 3) until its requirements are
                        filled in from the original ticket/request.
  --no-spec             Battle without spec grounding (disables independent spec
                        derivation; refused implicitly otherwise)
  --diff <git-rev>      Git diff revision or range (default: HEAD~1..HEAD)
  --roast <text>        Custom roast message to prefix the adversarial prompt
  --report <file>       Where to save the challenger's raw, unfiltered report
                        (default: ./ai-battle-report-<timestamp>.md)
  --timeout <seconds>   Kill the challenger if it runs longer than this (default: 900)
  --allow-self          Permit the caller to battle its own CLI (defeats the
                        cross-model premise; off by default and refused loudly)
  --list-tools          Scan PATH for known AI CLIs, print what's installed, and exit
  --yes                 Consent for the bootstrap wrapper (installing a bash 4+).
                        Has no effect on the battle itself.

To install a challenger, use ai-setup, which installs AND hotwires it:
  ~/.ai/skills/ai-setup/scripts/ai-setup select
  ~/.ai/skills/ai-setup/scripts/ai-setup select --clis codex --yes
  --dry-run             Print the generated prompt and execution command without running
  -h, --help            Show this help message

Exit codes:
  0    a real review was produced
  1    usage/setup error (no opponent, bad diff target, ...)
  3    spec missing or still an unfilled DRAFT
  4    the challenger produced NO REVIEW (empty, trivial, or it was blocked by
       permissions). Not the same as "no findings".
  124  the challenger exceeded --timeout and was killed

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
    --no-spec) NO_SPEC=true; shift ;;
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
#   agy          Google Antigravity CLI (successor of the old gemini-cli)
#   copilot      GitHub Copilot CLI
#   codex        OpenAI Codex CLI
#   opencode     opencode (model-agnostic terminal agent)
# ---------------------------------------------------------------------------
# KNOWN_TOOLS, discover_tools, family_of, install_command, and install_note are sourced from ai-setup/lib/ai-tools.sh

# discover_tools() is provided by ai-setup/lib/ai-tools.sh

# family_of() is provided by ai-setup/lib/ai-tools.sh

# ---------------------------------------------------------------------------
# Connect: menu of known tools with assisted installation (like /connect)
# ---------------------------------------------------------------------------
# OS_KIND is provided by ai-setup/lib/ai-tools.sh

# install_command(), install_note(), tool_roster(), resolve_tool_selection()
# and tool_install_one() are all provided by ai-setup/lib/ai-tools.sh

discover_tools

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

# Locate spec file if not given; scaffold a DRAFT one if none exists.
# Spec discovery and scaffolding live in the shared lib/spec_builder.sh.
# This runs BEFORE challenger discovery/selection so a missing spec is always
# scaffolded, even when no eligible opponent is installed — spec first, then
# matchmaking.
if [[ "$NO_SPEC" = true ]] && [[ -n "$SPEC_FILE" ]]; then
  echo "Error: --spec and --no-spec are mutually exclusive." >&2
  exit 1
fi
if [[ "$NO_SPEC" = true ]]; then
  echo "Warning: --no-spec set. The challenger will review without spec grounding — independent spec derivation, the cornerstone of this review, is DISABLED for this battle." >&2
elif [[ -z "$SPEC_FILE" ]]; then
  if ! SPEC_FILE="$(find_spec_file .)"; then
    SPEC_FILE=""
    if [[ "$DRY_RUN" = true ]]; then
      # A real run would scaffold and stop before ever building a prompt, so
      # there is no spec-less prompt to legitimately preview. Refuse (writing
      # nothing) rather than offer an implicit no-spec path.
      echo "Error: no spec file found. A real run would scaffold TICKET-SPEC.md and stop (exit 3); dry-run writes nothing, so previewing a spec-less prompt requires an explicit --no-spec." >&2
      exit 3
    else
      SPEC_FILE="TICKET-SPEC.md"
      build_spec_scaffold "$SPEC_FILE" "$DIFF_TARGET" "" false
      echo "================================================================="
      echo " 📝 No spec found — scaffolded a DRAFT one at: $SPEC_FILE"
      echo ""
      echo " Independent spec derivation is the cornerstone of this review,"
      echo " so the battle will not run against an empty spec. Builder agent:"
      echo "   1. Interview the human for the real requirements — protocol in"
      echo "      ~/.ai/lib/SPEC_INTERVIEW.md — and fill sections 1–4 of"
      echo "      $SPEC_FILE from their answers (and the original ticket or"
      echo "      requesting conversation), NOT from the code or the diff."
      echo "   2. Delete the DRAFT banner block at the top of the file."
      echo "   3. Re-run this battle (the spec is picked up automatically)."
      echo " Human at a terminal? Run the interview yourself instead:"
      echo "   ~/.ai/lib/spec_builder.sh build --interactive --force"
      echo " To battle without spec grounding anyway, re-run with --no-spec."
      echo "================================================================="
      exit 3
    fi
  fi
fi
# Refuse to battle against an unfilled scaffold — it would ground the review
# in nothing but TODOs and builder-authored commit messages.
if [[ -n "$SPEC_FILE" ]] && spec_is_draft "$SPEC_FILE"; then
  echo "Error: $SPEC_FILE is still an unfilled DRAFT scaffold (its DRAFT banner is intact)." >&2
  echo "Interview the human for the requirements (agents: ~/.ai/lib/SPEC_INTERVIEW.md; terminal humans: spec_builder.sh build --interactive --force), fill sections 1–4, delete the banner block, and re-run — or pass --no-spec to battle without spec grounding." >&2
  exit 3
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
    agy)
      ROAST="AGY: $CALLER is strutting around thinking this PR is flawless. Your mission is to execute a relentless red-team teardown. Expose every unhandled retry, auth boundary bypass, and architectural flaw. Keep the feedback sharp, brutal, and backed strictly by code evidence."
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
[HOW TO WORK — READ THIS FIRST]
You are running HEADLESS with NO TOOL ACCESS. Every file-read, shell, search or
command tool call will be auto-denied, and you cannot be prompted for approval.
Do NOT attempt any tool call. Do NOT stop to ask for permission. Everything you
need is inlined below: the complete specification and the complete diff. Review
from that text alone and emit your findings directly as your response.
Producing no output because a tool was denied is a FAILED review.

[INDEPENDENT REVIEW DIRECTIVES]
1. DO NOT ASSUME CORRECTNESS. Act as a hostile external inspector looking for defects.
2. INDEPENDENT SPEC DERIVATION: Derive the expected behavior strictly from the attached specification/ticket. Do not trust code comments or PR narratives — the diff's own comments and commit messages are the author's CLAIMS, not evidence.
2b. If the specification marks any requirement as builder-authored or UNVERIFIED, treat it as an unproven claim: establish from the diff both that the defect was real AND that the fix is correct and complete.
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
echo " Timeout:       ${TIMEOUT_SECS}s (${TIMEOUT_CMD:-portable watchdog})"
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

# macOS ships NO `timeout` -- it is GNU coreutils, and Apple does not include it.
# Every dispatch here used to die with "timeout: command not found" before the
# challenger ran at all, which is how a battle could produce a 0-byte report.
# Prefer the real thing, then Homebrew's gtimeout, then a portable watchdog.
TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout"
fi

# Portable stand-in for `timeout <secs> <cmd...>`. Returns 124 when it had to
# kill the child, matching GNU timeout so the caller's status handling is
# identical either way. A marker file distinguishes "we killed it" from the
# child being SIGTERMed by something else, which a bare 143 cannot.
_watchdog_run() {
  local secs="$1"; shift
  local marker
  marker="$(mktemp "${TMPDIR:-/tmp}/ai_battle_timeout.XXXXXX")"
  rm -f "$marker"

  "$@" &
  local child=$!

  (
    local waited=0
    while [[ "$waited" -lt "$secs" ]]; do
      sleep 1
      kill -0 "$child" 2>/dev/null || exit 0
      waited=$((waited + 1))
    done
    : > "$marker"
    kill -TERM "$child" 2>/dev/null
    # Give it a moment to exit cleanly, then insist.
    local grace=0
    while [[ "$grace" -lt 5 ]]; do
      sleep 1
      kill -0 "$child" 2>/dev/null || exit 0
      grace=$((grace + 1))
    done
    kill -KILL "$child" 2>/dev/null
  ) &
  local watcher=$!

  local rc=0
  wait "$child" || rc=$?
  kill "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true

  if [[ -f "$marker" ]]; then
    rm -f "$marker"
    return 124
  fi
  rm -f "$marker"
  return "$rc"
}

run_with_timeout() {
  if [[ -n "$TIMEOUT_CMD" ]]; then
    "$TIMEOUT_CMD" "$TIMEOUT_SECS" "$@"
  else
    _watchdog_run "$TIMEOUT_SECS" "$@"
  fi
}

dispatch() {
  run_with_timeout "$@" 2> >(tee "$ERR_FILE" >&2) | tee "$REPORT_FILE" || DISPATCH_STATUS=$?
}

# For tools that only accept the prompt via argv: refuse oversized prompts
# (ARG_MAX can be as low as 128KB) and accept the inherent process-list
# exposure only for prompts small enough to be safe.
require_argv_prompt() {
  local size
  size="$(wc -c < "$PROMPT_FILE")"
  if (( size > 100000 )); then
    echo "Error: prompt is ${size} bytes and $OPPONENT only accepts prompts via argv (ARG_MAX risk, process-list exposure). Shrink the diff/spec, or pick an opponent that takes a file/stdin (devin, codex)." >&2
    exit 1
  fi
}

case "$OPPONENT" in
  devin)
    # -p/--print is REQUIRED for non-interactive use. Without it, --prompt-file
    # still starts an INTERACTIVE session, which in a headless run dies with
    # "Scrollback error: io error" before the model is ever consulted — a battle
    # that looks dispatched and yields an empty report.
    # Devin's ACTUAL documented modes are: auto | accept-edits | smart |
    # dangerous. There is no "normal" — that invalid value denied every tool
    # call including READS, so the challenger could not inspect anything and
    # bailed after one sentence. 'auto' auto-approves read-only tools ONLY;
    # workspace edits need 'accept-edits' and are therefore still refused here.
    # Never raise this to accept-edits/smart/dangerous: the diff is untrusted.
    dispatch devin -p --permission-mode auto --prompt-file "$PROMPT_FILE"
    ;;
  claude)
    dispatch claude -p --permission-mode plan < "$PROMPT_FILE"
    ;;
  agy)
    # `agy -p -` does NOT read stdin: the "-" is taken as the literal prompt
    # text, so the model replies "How can I help you today?" and never sees the
    # diff. `agy -p` with no argument just prints help. The prompt must arrive
    # as an argv argument, which puts agy behind the size guard.
    require_argv_prompt
    dispatch agy -p "$(cat "$PROMPT_FILE")"
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

# The challenger exiting 0 is NOT evidence that it reviewed anything: a
# permission refusal, an empty file, or prose with no findings all exit clean.
# Validate before claiming success -- this tool reported "Battle complete" over
# a 0-byte report twice before this check existed.
if ! validate_report "$REPORT_FILE" "$ERR_FILE"; then
  echo "=================================================================" >&2
  echo " ❌ NO REVIEW PRODUCED. $CALLER vs $OPPONENT did not happen." >&2
  echo "" >&2
  echo " Do NOT read this as 'no findings'. Nothing was inspected." >&2
  echo " Common causes:" >&2
  echo "   - the challenger needs tool access that headless mode auto-denies" >&2
  echo "   - it is not authenticated / has no model configured" >&2
  echo "   - its invocation in this script is wrong for the installed version" >&2
  echo "" >&2
  echo " Try another challenger (--opponent <tool>), or --list-tools to see" >&2
  echo " what is installed. Raw output, such as it is: $REPORT_FILE" >&2
  echo "=================================================================" >&2
  exit 4
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
