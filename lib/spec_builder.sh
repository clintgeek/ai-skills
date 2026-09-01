#!/usr/bin/env bash
# Shared spec locator & scaffolder for AI skills.
#
# Several skills need a specification file to ground their work (ai-battle's
# "independent spec derivation" is the first consumer). This is the one place
# spec discovery and spec scaffolding live — source it or call it, never copy it.
#
# CLI usage:
#   spec_builder.sh find   [--dir <path>]
#       Print the path of an existing spec file (TICKET-SPEC.md, SPEC.md,
#       *SPEC.md, *spec.md) and exit 0; exit 1 if none exists.
#   spec_builder.sh build  [--out <file>] [--diff <range>] [--title <text>] [--force] [--interactive]
#       Scaffold a DRAFT spec at <file> (default: TICKET-SPEC.md), pre-filled
#       with auto-collected git evidence (branch, commits, diffstat, ticket IDs)
#       and TODO sections for the real requirements. Refuses to overwrite
#       without --force. With --interactive (terminal only), interviews the
#       human for each section first; a spec whose Intent and Requirements were
#       both answered is written WITHOUT the DRAFT banner (battle-ready).
#       Exit 3 if what was written is still a DRAFT (the usual case without
#       --interactive), 0 only for a battle-ready spec.
#   spec_builder.sh ensure [--dir <path>] [--out <file>] [--diff <range>] [--title <text>] [--interactive]
#       find, else build. Prints the spec path. Exit 0 if a COMPLETE spec
#       already existed or the interview produced one; exit 3 if the spec that
#       was found or written is still an unfilled DRAFT. A stale draft never
#       counts as found — with --interactive it triggers the interview and is
#       overwritten in place.
#
# Library usage (sourcing defines functions and runs nothing):
#   source lib/spec_builder.sh
#   find_spec_file [<dir>]                        # prints path; rc 1 if none
#   spec_is_draft <file>                          # rc 0 if still an unfilled scaffold
#   run_spec_interview [<diff-range>]             # TTY-interview the human; fills SPEC_* vars
#   build_spec_scaffold <out> <diff-range> <title> <force>
#
# AI-agent sessions have no TTY for --interactive. There, the AGENT conducts
# the interview with the user (protocol: lib/SPEC_INTERVIEW.md) and writes the
# answers into the spec itself — requirements must come from the human/ticket,
# never from the agent's own reading of the code.
#
# IMPORTANT: a scaffolded spec is NOT a spec. Its requirements sections must be
# filled from the ORIGINAL ticket / request / conversation — never reverse-
# engineered from the code or diff, which would make any review of that code
# against it a rubber stamp.

SPEC_DRAFT_MARKER="Status: DRAFT — requirements not yet confirmed"

# Section content consumed by build_spec_scaffold. Filled by run_spec_interview,
# or set directly by a sourcing script. Empty Intent/Requirements ⇒ the output
# keeps its DRAFT banner; empty sections render as TODO placeholders.
SPEC_INTENT="${SPEC_INTENT:-}"
SPEC_REQUIREMENTS="${SPEC_REQUIREMENTS:-}"
SPEC_OUT_OF_SCOPE="${SPEC_OUT_OF_SCOPE:-}"
SPEC_INVARIANTS="${SPEC_INVARIANTS:-}"

find_spec_file() {
  local dir="${1:-.}" candidate
  # Exact conventional names first, then loose matches. An unmatched glob stays
  # literal and fails the -f test, so no nullglob is needed — this function must
  # be safe to call from a sourcing script without mutating its shell options.
  for candidate in "$dir"/TICKET-SPEC.md "$dir"/SPEC.md "$dir"/*SPEC.md "$dir"/*spec.md; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

spec_is_draft() {
  [[ -f "${1:-}" ]] && grep -qF "$SPEC_DRAFT_MARKER" "$1"
}

build_spec_scaffold() {
  local out="${1:-TICKET-SPEC.md}"
  local diff_target="${2:-HEAD~1..HEAD}"
  local title="${3:-}"
  local force="${4:-false}"

  if [[ -f "$out" ]] && [[ "$force" != true ]]; then
    echo "Error: $out already exists — refusing to overwrite (use --force)." >&2
    return 1
  fi

  # Auto-collect neutral evidence from git. This is context, not requirements:
  # commit messages are builder-authored, so the template labels them as
  # evidence and keeps the requirements sections as explicit TODOs.
  local in_git=false branch="" commits="" diffstat="" tickets=""
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    in_git=true
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    commits="$(git log --no-merges --format='* %s%n%w(76,2,2)%b' "$diff_target" 2>/dev/null || true)"
    diffstat="$(git diff --stat "$diff_target" 2>/dev/null || true)"
    tickets="$(printf '%s\n%s\n' "$branch" "$commits" | grep -oE '[A-Z][A-Z0-9]{1,9}-[0-9]+' | sort -u | paste -sd ', ' - || true)"
  fi

  if [[ -z "$title" ]]; then
    if [[ -n "$branch" ]] && [[ "$branch" != "HEAD" ]]; then
      title="$branch"
    else
      title="$(basename "$PWD")"
    fi
  fi

  # The DRAFT banner stays on until the load-bearing sections (Intent and
  # Requirements) hold real content — from the interview or a sourcing script.
  local draft=false
  if [[ -z "$SPEC_INTENT" ]] || [[ -z "$SPEC_REQUIREMENTS" ]]; then
    draft=true
  fi

  {
    printf '# Specification: %s\n\n' "$title"
    if [[ "$draft" = true ]]; then
      printf '> **%s.**\n' "$SPEC_DRAFT_MARKER"
      cat << 'EOF'
> ⚠️  Fill sections 1–4 from the ORIGINAL requirements source — the ticket or
> issue, or in repos without one, the conversation that asked for this work —
> NOT from the code or the diff. A spec reverse-engineered from the
> implementation can only prove the code does what the code does, which
> defeats independent review.
> Delete this banner block once the requirements below are real.
>
EOF
    fi
    printf '> Scaffolded by spec_builder.sh on %s' "$(date +%Y-%m-%d)"
    if [[ "$in_git" = true ]]; then
      printf ' (branch `%s`, diff `%s`)' "${branch:-?}" "$diff_target"
    fi
    printf '.\n\n'

    printf '## 1. Intent\n'
    if [[ -n "$SPEC_INTENT" ]]; then
      printf '%s\n\n' "$SPEC_INTENT"
    else
      printf '<!-- TODO: What problem does this change solve, and for whom? One or two paragraphs. -->\n\n'
    fi

    printf '## 2. Requirements / Acceptance Criteria\n'
    if [[ -n "$SPEC_REQUIREMENTS" ]]; then
      printf '%s\n\n' "$SPEC_REQUIREMENTS"
    else
      printf '<!-- TODO: Numbered, independently testable statements of required behavior. -->\n1.\n\n'
    fi

    printf '## 3. Out of Scope\n'
    if [[ -n "$SPEC_OUT_OF_SCOPE" ]]; then
      printf '%s\n\n' "$SPEC_OUT_OF_SCOPE"
    else
      printf '<!-- TODO: What this change deliberately does not do. -->\n\n'
    fi

    printf '## 4. Invariants That Must Not Break\n'
    if [[ -n "$SPEC_INVARIANTS" ]]; then
      printf '%s\n\n' "$SPEC_INVARIANTS"
    else
      printf '<!-- TODO: Domain rules, auth boundaries, API contracts, downstream consumers. -->\n\n'
    fi

    printf '## 5. Evidence From the Working Tree (auto-collected — context, not requirements)\n'
    if [[ "$in_git" = true ]]; then
      printf '\n* **Branch:** `%s`\n' "${branch:-unknown}"
      printf '* **Diff target:** `%s`\n' "$diff_target"
      if [[ -n "$tickets" ]]; then
        printf '* **Ticket references detected:** %s\n' "$tickets"
      fi
      if [[ -n "$commits" ]]; then
        printf '\n### Commit messages in range\n\n%s\n' "$commits"
      fi
      if [[ -n "$diffstat" ]]; then
        printf '\n### Diffstat\n\n```text\n%s\n```\n' "$diffstat"
      fi
    else
      printf '\n*(Not a git repository — no evidence collected.)*\n'
    fi
  } > "$out"
}

# Read a multi-line answer until a lone '.' or EOF. A lone '.' straight away
# (or Ctrl-D) skips the section.
_spec_interview_read() {
  local line lines=()
  while IFS= read -r line; do
    [[ "$line" == "." ]] && break
    lines+=("$line")
  done
  if (( ${#lines[@]} > 0 )); then
    printf '%s\n' "${lines[@]}"
  fi
}

# Interview the HUMAN at the terminal for the spec's four sections, filling the
# SPEC_* variables. The whole point is that requirements come from the person
# who owns them — not from anyone's reading of the code — so this refuses to
# run without a TTY. Agent-driven sessions must interview the user in
# conversation instead (protocol: lib/SPEC_INTERVIEW.md).
run_spec_interview() {
  local diff_target="${1:-HEAD~1..HEAD}"
  if [[ ! -t 0 ]]; then
    echo "Error: --interactive needs a terminal (stdin is not a TTY)." >&2
    echo "AI-agent session? Interview the user yourself following lib/SPEC_INTERVIEW.md, then write their answers into the spec." >&2
    return 1
  fi

  echo ""
  echo "📋 Spec interview — answers come from YOU, not from the code."
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "   Context: branch $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?'), diff $diff_target"
    git log --no-merges --format='   • %s' "$diff_target" 2>/dev/null | head -10 || true
  fi
  echo "   End each answer with a single '.' on its own line; '.' immediately skips a section."
  echo ""

  echo "1/4 Intent — what problem does this change solve, and for whom?"
  SPEC_INTENT="$(_spec_interview_read)"
  echo ""
  echo "2/4 Requirements — numbered, testable acceptance criteria. What must be true for this to count as done?"
  SPEC_REQUIREMENTS="$(_spec_interview_read)"
  echo ""
  echo "3/4 Out of scope — what does this change deliberately NOT do?"
  SPEC_OUT_OF_SCOPE="$(_spec_interview_read)"
  [[ -z "$SPEC_OUT_OF_SCOPE" ]] && SPEC_OUT_OF_SCOPE="*(None specified.)*"
  echo ""
  echo "4/4 Invariants — what must not break? (domain rules, auth boundaries, API contracts, downstream consumers)"
  SPEC_INVARIANTS="$(_spec_interview_read)"
  [[ -z "$SPEC_INVARIANTS" ]] && SPEC_INVARIANTS="*(None specified.)*"
  echo ""

  if [[ -z "$SPEC_INTENT" ]] || [[ -z "$SPEC_REQUIREMENTS" ]]; then
    echo "Intent and/or Requirements were skipped — the spec will keep its DRAFT banner until they are filled." >&2
  fi
  return 0
}

_spec_builder_usage() {
  cat << 'EOF'
spec_builder.sh: locate an existing spec file or scaffold a DRAFT one

Usage:
  spec_builder.sh find   [--dir <path>]
  spec_builder.sh build  [--out <file>] [--diff <range>] [--title <text>] [--force] [--interactive]
  spec_builder.sh ensure [--dir <path>] [--out <file>] [--diff <range>] [--title <text>] [--interactive]

Options:
  --dir <path>     Directory to search for an existing spec (default: .)
  --out <file>     Where to write the scaffold (default: <dir>/TICKET-SPEC.md)
  --diff <range>   Git range whose commits/diffstat are collected as evidence
                   (default: HEAD~1..HEAD)
  --title <text>   Spec title (default: current branch name, else directory name)
  --force          Overwrite an existing --out file (build only)
  --interactive    Interview the human at the terminal for Intent, Requirements,
                   Out of Scope, and Invariants before writing. Requires a TTY —
                   AI-agent sessions interview the user in conversation instead
                   (see lib/SPEC_INTERVIEW.md). Answering Intent and Requirements
                   writes a banner-free, battle-ready spec.
  -h, --help       Show this help

Exit codes:
  0  find/ensure located a completed spec, or the written spec is complete
  1  error (find: no spec found; build: refusing to overwrite; no TTY; bad flags)
  3  the spec found or written is still a DRAFT needing its requirements filled
     (a stale unfilled draft never counts as a completed spec)
EOF
}

_spec_builder_main() {
  set -euo pipefail
  local cmd="${1:-}"
  [[ $# -gt 0 ]] && shift
  local dir="." out="" diff_target="HEAD~1..HEAD" title="" force=false interactive=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dir)
        [[ $# -lt 2 ]] && { echo "Error: --dir requires an argument" >&2; return 1; }
        dir="$2"; shift 2 ;;
      --out)
        [[ $# -lt 2 ]] && { echo "Error: --out requires an argument" >&2; return 1; }
        out="$2"; shift 2 ;;
      --diff)
        [[ $# -lt 2 ]] && { echo "Error: --diff requires an argument" >&2; return 1; }
        diff_target="$2"; shift 2 ;;
      --title)
        [[ $# -lt 2 ]] && { echo "Error: --title requires an argument" >&2; return 1; }
        title="$2"; shift 2 ;;
      --force) force=true; shift ;;
      --interactive) interactive=true; shift ;;
      -h|--help) _spec_builder_usage; return 0 ;;
      *) echo "Unknown option: $1" >&2; return 1 ;;
    esac
  done
  [[ -z "$out" ]] && out="$dir/TICKET-SPEC.md"

  local found
  case "$cmd" in
    find)
      find_spec_file "$dir" ;;
    build)
      if [[ "$interactive" = true ]]; then
        run_spec_interview "$diff_target" || return 1
      fi
      build_spec_scaffold "$out" "$diff_target" "$title" "$force"
      echo "$out"
      # Exit 3 whenever what we wrote is still a DRAFT, however we were called.
      # This used to be gated on --interactive, so a plain `build` always
      # scaffolded a TODO-only spec and reported success -- contradicting the
      # documented exit codes and letting a caller treat a placeholder as done.
      if spec_is_draft "$out"; then
        if [[ "$interactive" = true ]]; then
          echo "Spec written, but it is still a DRAFT — Intent and/or Requirements were skipped." >&2
        else
          echo "Scaffolded a DRAFT spec — fill sections 1–4 from the original ticket/request, then delete the DRAFT banner (or re-run with --interactive in a terminal)." >&2
        fi
        return 3
      fi ;;
    ensure)
      if found="$(find_spec_file "$dir")"; then
        # A found spec only counts if its requirements are real. A stale
        # unfilled scaffold must NOT short-circuit the interview — treat it
        # like a missing spec (and with --interactive, interview over it).
        if ! spec_is_draft "$found"; then
          echo "$found"
          return 0
        fi
        if [[ "$interactive" = true ]]; then
          run_spec_interview "$diff_target" || return 1
          build_spec_scaffold "$found" "$diff_target" "$title" true
        fi
        echo "$found"
        if spec_is_draft "$found"; then
          echo "Existing $found is still an unfilled DRAFT — fill sections 1–4 from the original ticket/request, then delete the DRAFT banner (or re-run with --interactive in a terminal)." >&2
          return 3
        fi
        echo "Spec written from interview answers — battle-ready." >&2
        return 0
      fi
      if [[ "$interactive" = true ]]; then
        run_spec_interview "$diff_target" || return 1
      fi
      build_spec_scaffold "$out" "$diff_target" "$title" false
      echo "$out"
      if spec_is_draft "$out"; then
        echo "Scaffolded a DRAFT spec — fill sections 1–4 from the original ticket/request, then delete the DRAFT banner (or re-run with --interactive in a terminal)." >&2
        return 3
      fi
      echo "Spec written from interview answers — battle-ready." >&2 ;;
    ""|help)
      _spec_builder_usage ;;
    *)
      echo "Unknown command: $cmd" >&2
      _spec_builder_usage >&2
      return 1 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _spec_builder_main "$@"
fi
