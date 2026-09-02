#!/usr/bin/env bash
# Shared spec locator & scaffolder for AI skills.
#
# Several skills need a specification file to ground their work (ai-battle's
# "independent spec derivation" is the first consumer). This is the one place
# spec discovery and spec scaffolding live — source it or call it, never copy it.
#
# CLI usage:
#   spec_builder.sh find   [--dir <path>]
#       Print the best existing spec (searching ., DOCS/, docs/, doc/) and exit 0;
#       exit 1 if none exists.
#   spec_builder.sh list   [--dir <path>]
#       Print EVERY spec-shaped file found, one per line. Use this when talking
#       to a human: a project may have several and only they know which applies.
#   spec_builder.sh build  [--out <file>] [--title <text>] [--force]
#       Write an empty DRAFT skeleton (default: DOCS/TICKET-SPEC.md where DOCS
#       exists, else ./TICKET-SPEC.md). Refuses to overwrite without --force.
#       Exit 3, because a skeleton is not a spec until a human fills it.
#   spec_builder.sh ensure [--dir <path>] [--out <file>] [--title <text>]
#       find, else build. Prints the path. Exit 0 only if a COMPLETE spec already
#       existed; exit 3 if what was found or written is still an unfilled DRAFT.
#
# Library usage (sourcing defines functions and runs nothing):
#   source lib/spec_builder.sh
#   list_spec_files [<root>]                      # every match, one per line
#   find_spec_file  [<root>]                      # best match; rc 1 if none
#   default_spec_path [<root>]                    # where a new spec belongs
#   spec_is_draft <file>                          # rc 0 if still an unfilled skeleton
#   build_spec_scaffold <out> [title] [force]
#
# THERE IS NO --interactive. There used to be a TTY prompt loop here, which was
# a second implementation of the interview and one nothing could run: this repo's
# entry point is an agent, and the script refused without a terminal. The
# interview belongs in CONVERSATION -- skills/spec-builder/SKILL.md and
# lib/SPEC_INTERVIEW.md -- where the human can be asked follow-up questions.
#
# IMPORTANT: a scaffold is NOT a spec. Its sections must be filled from what the
# HUMAN wants -- the ticket, the issue, the conversation that asked for the work
# -- never reverse-engineered from the code. A builder writing its own spec is
# asking the bank robber how much he took.

SPEC_DRAFT_MARKER="Status: DRAFT — requirements not yet confirmed"

# Section content consumed by build_spec_scaffold. Set these from the answers a
# human gave in conversation. Empty Intent/Requirements ⇒ the output
# keeps its DRAFT banner; empty sections render as TODO placeholders.
SPEC_INTENT="${SPEC_INTENT:-}"
SPEC_REQUIREMENTS="${SPEC_REQUIREMENTS:-}"
SPEC_OUT_OF_SCOPE="${SPEC_OUT_OF_SCOPE:-}"
SPEC_INVARIANTS="${SPEC_INVARIANTS:-}"

# Directories a project might keep a spec in. Searched in order.
SPEC_SEARCH_DIRS="${SPEC_SEARCH_DIRS:-. DOCS docs doc}"

# Every spec-shaped file in the project, one per line, best match first.
# Searching only "." missed DOCS/ -- which is where this repo keeps all three of
# its own specs, so "find a spec in the project" was a coin flip.
list_spec_files() {
  local root="${1:-.}" dir candidate seen="" d dup
  local -a seen_dirs=()
  for dir in $SPEC_SEARCH_DIRS; do
    [[ -d "$root/$dir" ]] || continue
    # -ef compares the actual file, not the string. macOS is case-insensitive,
    # so DOCS and docs are the SAME directory -- and `pwd -P` does not help,
    # because it resolves symlinks but preserves whatever case was typed.
    # ${arr[@]+"${arr[@]}"} because callers run under `set -u` and bash 3.2
    # errors on an empty array expansion.
    dup=false
    for d in ${seen_dirs[@]+"${seen_dirs[@]}"}; do
      [[ "$root/$dir" -ef "$d" ]] && { dup=true; break; }
    done
    [[ "$dup" == true ]] && continue
    seen_dirs+=("$root/$dir")
    for candidate in "$root/$dir"/TICKET-SPEC.md "$root/$dir"/SPEC.md \
                     "$root/$dir"/*SPEC*.md "$root/$dir"/*spec*.md; do
      [[ -f "$candidate" ]] || continue
      case " $seen " in *" $candidate "*) continue ;; esac
      seen="$seen $candidate"
      echo "$candidate"
    done
  done
  [[ -n "$seen" ]]
}

# The single best match, for callers that need one path (ai-battle). Agents
# should use list_spec_files and DISCUSS what they find with the human.
find_spec_file() {
  list_spec_files "${1:-.}" | head -1
  # head -1 masks the pipeline status, so ask again.
  list_spec_files "${1:-.}" >/dev/null
}

# Where a NEW spec should go. A project that keeps docs in DOCS/ should get its
# spec there too, rather than a stray file in the root.
default_spec_path() {
  local root="${1:-.}" dir
  for dir in DOCS docs doc; do
    [[ -d "$root/$dir" ]] && { echo "$root/$dir/TICKET-SPEC.md"; return 0; }
  done
  echo "$root/TICKET-SPEC.md"
}

spec_is_draft() {
  [[ -f "${1:-}" ]] && grep -qF "$SPEC_DRAFT_MARKER" "$1"
}

# Write an EMPTY spec skeleton. Deliberately no git evidence.
#
# This used to pre-fill branch name, commit subjects, diffstat and detected
# ticket IDs. All of that is the BUILDER's account of its own work -- asking the
# bank robber how much he took -- and it anchored the conversation on the
# implementation before the human had said what they wanted. On genuinely new
# work there are no commits to collect anyway.
#
#   build_spec_scaffold <out> [title] [force]
build_spec_scaffold() {
  local out="${1:-TICKET-SPEC.md}"
  local title="${2:-}"
  local force="${3:-false}"

  if [[ -f "$out" ]] && [[ "$force" != true ]]; then
    echo "Error: $out already exists — refusing to overwrite (use --force)." >&2
    return 1
  fi
  [[ -z "$title" ]] && title="$(basename "$PWD")"

  local draft=false
  if [[ -z "$SPEC_INTENT" ]] || [[ -z "$SPEC_REQUIREMENTS" ]]; then
    draft=true
  fi

  {
    printf '# Specification: %s\n\n' "$title"
    if [[ "$draft" = true ]]; then
      printf '> **%s.**\n' "$SPEC_DRAFT_MARKER"
      cat << 'EOF'
> ⚠️  Fill sections 1–4 from what the HUMAN wants — the ticket, the issue, or the
> conversation that asked for this work. Never from the code or the diff. A spec
> reverse-engineered from the implementation can only prove the code does what
> the code does, which is not a review.
> Delete this banner block once the requirements below are real.
>
EOF
    fi
    printf '> Scaffolded by spec_builder.sh on %s.\n\n' "$(date +%Y-%m-%d)"

    printf '## 1. Intent\n'
    if [[ -n "$SPEC_INTENT" ]]; then printf '%s\n\n' "$SPEC_INTENT"
    else printf '<!-- What problem does this solve, and for whom? One or two paragraphs. -->\n\n'; fi

    printf '## 2. Requirements / Acceptance Criteria\n'
    if [[ -n "$SPEC_REQUIREMENTS" ]]; then printf '%s\n\n' "$SPEC_REQUIREMENTS"
    else printf '<!-- Numbered, independently testable statements of required behavior. -->\n1.\n\n'; fi

    printf '## 3. Out of Scope\n'
    if [[ -n "$SPEC_OUT_OF_SCOPE" ]]; then printf '%s\n\n' "$SPEC_OUT_OF_SCOPE"
    else printf '<!-- What this deliberately does not do. -->\n\n'; fi

    printf '## 4. Invariants That Must Not Break\n'
    if [[ -n "$SPEC_INVARIANTS" ]]; then printf '%s\n\n' "$SPEC_INVARIANTS"
    else printf '<!-- Domain rules, auth boundaries, API contracts, downstream consumers. -->\n\n'; fi
  } > "$out"
}

_spec_builder_usage() {
  cat << 'EOF'
spec_builder.sh: locate an existing spec, or scaffold an empty one

Usage:
  spec_builder.sh find   [--dir <path>]
  spec_builder.sh list   [--dir <path>]
  spec_builder.sh build  [--out <file>] [--title <text>] [--force]
  spec_builder.sh ensure [--dir <path>] [--out <file>] [--title <text>]

Options:
  --dir <path>     Project root to search (default: .)
                   Searches ., DOCS/, docs/, doc/
  --out <file>     Where to write (default: DOCS/TICKET-SPEC.md if DOCS exists,
                   else ./TICKET-SPEC.md)
  --title <text>   Spec title (default: the directory name)
  --force          Overwrite an existing --out file (build only)
  -h, --help       Show this help

Exit codes:
  0  find/ensure located a COMPLETE spec
  1  error (find: none found; build: refusing to overwrite; bad flags)
  3  the spec found or written is still an unfilled DRAFT

The interview is a CONVERSATION, not a flag. See skills/spec-builder/SKILL.md.
EOF
}

_spec_builder_main() {
  set -euo pipefail
  local cmd="${1:-}"
  [[ $# -gt 0 ]] && shift
  local dir="." out="" title="" force=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dir)
        [[ $# -lt 2 ]] && { echo "Error: --dir requires an argument" >&2; return 1; }
        dir="$2"; shift 2 ;;
      --out)
        [[ $# -lt 2 ]] && { echo "Error: --out requires an argument" >&2; return 1; }
        out="$2"; shift 2 ;;
      --title)
        [[ $# -lt 2 ]] && { echo "Error: --title requires an argument" >&2; return 1; }
        title="$2"; shift 2 ;;
      --force) force=true; shift ;;
      -h|--help) _spec_builder_usage; return 0 ;;
      *) echo "Unknown option: $1" >&2; return 1 ;;
    esac
  done
  [[ -z "$out" ]] && out="$(default_spec_path "$dir")"

  local found
  case "$cmd" in
    find)
      find_spec_file "$dir" ;;
    list)
      list_spec_files "$dir" ;;
    build)
      build_spec_scaffold "$out" "$title" "$force" || return 1
      echo "$out"
      if spec_is_draft "$out"; then
        echo "Scaffolded an empty DRAFT — fill sections 1-4 from what the human wants, in conversation, then delete the DRAFT banner." >&2
        return 3
      fi ;;
    ensure)
      if found="$(find_spec_file "$dir")" && [[ -n "$found" ]]; then
        echo "$found"
        if spec_is_draft "$found"; then
          echo "$found is still an unfilled DRAFT — fill sections 1-4 in conversation with the human, then delete the DRAFT banner." >&2
          return 3
        fi
        return 0
      fi
      build_spec_scaffold "$out" "$title" false || return 1
      echo "$out"
      if spec_is_draft "$out"; then
        echo "Scaffolded an empty DRAFT — fill sections 1-4 from what the human wants, in conversation, then delete the DRAFT banner." >&2
        return 3
      fi ;;
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
