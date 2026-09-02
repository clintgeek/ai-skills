#!/usr/bin/env bash
# Regression tests for lib/spec_builder.sh and its battle_runner.sh integration.
# Run: ~/.ai/lib/tests/spec_builder_test.sh   (exit 0 = all pass)
#
# Covers the three findings from the 2026-08-31 ai-battle (Codex challenger):
#   F1: a stale unfilled DRAFT must not make `ensure` exit 0
#   F2: spec-less --dry-run must refuse (exit 3, write nothing) without --no-spec
#   F3: a missing spec must be scaffolded even when no AI CLI is on PATH
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SB="$SCRIPT_DIR/../spec_builder.sh"
BR="$SCRIPT_DIR/../../skills/ai-battle/scripts/battle_runner.sh"

PASS=0 FAIL=0
check() { # check <description> <expected-rc> <actual-rc>
  if [[ "$2" == "$3" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $1"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $1 (expected rc $2, got $3)" >&2
  fi
}
assert() { # assert <description> <condition-rc (0 = true)>
  if [[ "$2" -eq 0 ]]; then
    PASS=$((PASS + 1)); echo "  ok: $1"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2
  fi
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/spec_builder_test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM
cd "$WORK"
git init -q -b feature/TEST-1 . && git config user.email t@t && git config user.name t
echo a > a.txt && git add . && git commit -qm "TEST-1: first"
echo b >> a.txt && git commit -qam "second"

echo "== core =="
"$SB" find >/dev/null 2>&1;                       check "find with no spec exits 1" 1 $?
"$SB" ensure --out TICKET-SPEC.md >/dev/null 2>&1;                     check "ensure scaffolds a DRAFT and exits 3" 3 $?
grep -q "Status: DRAFT" TICKET-SPEC.md;           assert "scaffold carries the DRAFT banner" $?
# The scaffold is deliberately EMPTY now: git evidence (branch, commits,
# diffstat, ticket ids) is the builder's account of its own work, and it anchored
# the conversation on the implementation before the human had said anything.
! grep -q "TEST-1" TICKET-SPEC.md;               assert "scaffold contains NO git evidence" $?
! grep -qi "diffstat\|Commit messages" TICKET-SPEC.md; assert "  and no commit/diffstat block" $?
grep -q "## 1. Intent" TICKET-SPEC.md;           assert "  but does carry the 4-section skeleton" $?
"$SB" build --out TICKET-SPEC.md >/dev/null 2>&1; check "build refuses to overwrite without --force" 1 $?
# The documented contract is "3 = what was written is still a DRAFT". This used
# to be gated on --interactive, so a plain `build` reported success for a
# TODO-only scaffold and a caller could treat a placeholder as a real spec.
# Run in a scratch subdirectory: the checks below this block depend on $WORK
# still holding an unfilled DRAFT, so this must not touch it.
mkdir -p "$WORK/buildprobe" && pushd "$WORK/buildprobe" >/dev/null
"$SB" build --out TICKET-SPEC.md >/dev/null 2>&1;                      check "build of a DRAFT exits 3, not 0" 3 $?
grep -q "Status: DRAFT" TICKET-SPEC.md;           assert "  and the file really is a draft" $?
rm -f TICKET-SPEC.md
bash -c "source '$SB'
SPEC_INTENT='Filled.'
SPEC_REQUIREMENTS='1. Filled.'
_spec_builder_main build --out TICKET-SPEC.md" >/dev/null 2>&1
check "build of a complete spec exits 0" 0 $?
popd >/dev/null

echo "== discovery searches the PROJECT, not one directory =="
# It only ever looked in "." — which missed DOCS/, where this repo keeps all
# three of its own specs. "Find a spec in the project" was a coin flip.
mkdir -p sub/DOCS sub/src
printf '# Specification: thing\n\n## 1. Intent\nreal\n' > sub/DOCS/TICKET-SPEC.md
out="$("$SB" find --dir sub)"
check "finds a spec in DOCS/" "sub/DOCS/TICKET-SPEC.md" "$out"
# Control: it must NOT find one where there is none.
mkdir -p empty/src
"$SB" find --dir empty >/dev/null 2>&1
check "  (control) finds nothing in a project without one" 1 $?

# list shows EVERY match, because a project may have several and only the human
# knows which governs the work.
printf '# Specification: other\n' > sub/DOCS/THE_SPEC.md
n="$("$SB" list --dir sub | wc -l | tr -d ' ')"
check "list reports every spec it found" 2 "$n"

# A new spec belongs where the project keeps docs.
out="$(bash -c "source '$SB'; default_spec_path sub")"
check "a new spec lands in DOCS/ when it exists" "sub/DOCS/TICKET-SPEC.md" "$out"
out="$(bash -c "source '$SB'; default_spec_path empty")"
check "  and in the root when it does not" "empty/TICKET-SPEC.md" "$out"

echo "== there is no --interactive =="
# It was a TTY prompt loop nothing could run: this repo's entry point is an
# agent, and the script refused without a terminal. The interview is a
# conversation now (skills/spec-builder/SKILL.md).
"$SB" build --interactive --out /dev/null >/dev/null 2>&1
check "--interactive is rejected as an unknown flag" 1 $?
! grep -q "run_spec_interview" "$SB"
assert "  and the TTY interview function is gone" $?

echo "== F1: stale draft must not satisfy ensure =="
"$SB" ensure --out TICKET-SPEC.md >/dev/null 2>&1;                     check "ensure on an existing unfilled DRAFT exits 3" 3 $?
bash -c "source '$SB'
SPEC_INTENT='Test intent.'
SPEC_REQUIREMENTS='1. Testable requirement.'
build_spec_scaffold TICKET-SPEC.md '' true"
"$SB" ensure --out TICKET-SPEC.md >/dev/null 2>&1;                     check "ensure on a completed spec exits 0" 0 $?
bash -c "source '$SB'; spec_is_draft TICKET-SPEC.md"
check "completed spec has no DRAFT banner" 1 $?

echo "== F2: spec-less dry-run refuses without --no-spec =="
rm TICKET-SPEC.md
CALLING_AGENT=devin "$BR" --dry-run >/dev/null 2>&1
check "spec-less --dry-run exits 3" 3 $?
[[ ! -e TICKET-SPEC.md ]];                        assert "spec-less --dry-run writes nothing" $?
# What F2 is actually about: --no-spec BYPASSES the spec gate. Exit 3 means the
# gate fired; anything else means it did not. Asserting exit 0 additionally
# required an installed challenger, which is true on a dev laptop and false on a
# clean CI runner, where the run legitimately stops at "no AI CLIs on PATH".
out="$(CALLING_AGENT=devin "$BR" --dry-run --no-spec 2>&1)"; rc=$?
assert "spec-less --dry-run with --no-spec does not hit the spec gate (rc=$rc)" \
  $([[ "$rc" -ne 3 ]] && echo 0 || echo 1)
if [[ "$rc" -ne 0 ]]; then
  # Whatever stopped it must be about the challenger, not the spec.
  assert "  and any failure is challenger-related, not spec-related" \
    $(grep -qiE 'no external AI CLIs|only AI CLI|same model family' <<<"$out" && echo 0 || echo 1)
else
  assert "  and it previewed a prompt" $(grep -q 'DRY RUN' <<<"$out" && echo 0 || echo 1)
fi

echo "== F3: spec scaffolds before challenger selection =="
# Strip AI CLIs from PATH; keep system tools so git/grep still work.
# Narrowing to /usr/bin:/bin alone would also demote `bash` to macOS's 3.2,
# which cannot do associative arrays -- that fails the runner for the wrong
# reason. Expose only the bash running this suite, via a dir holding nothing
# else (the real bash dir may itself contain AI CLIs, e.g. agy in
# /opt/homebrew/bin).
BASH_ONLY_BIN="$WORK/.bash-only"
mkdir -p "$BASH_ONLY_BIN"
ln -s "$(command -v bash)" "$BASH_ONLY_BIN/bash"
NO_AI_PATH="$BASH_ONLY_BIN:/usr/bin:/bin"
PATH="$NO_AI_PATH" CALLING_AGENT=devin "$BR" >/dev/null 2>&1
check "no spec + no AI CLIs: scaffold-and-stop exits 3 (not tool error 1)" 3 $?
[[ -f TICKET-SPEC.md ]];                          assert "spec was scaffolded despite empty roster" $?
PATH="$NO_AI_PATH" CALLING_AGENT=devin "$BR" >/dev/null 2>&1
check "re-run with draft + no AI CLIs still exits 3 (draft refusal)" 3 $?

echo "== battle_runner spec gating =="
CALLING_AGENT=devin "$BR" --opponent claude >/dev/null 2>&1
check "battle against unfilled DRAFT exits 3" 3 $?
CALLING_AGENT=devin "$BR" --spec TICKET-SPEC.md --no-spec >/dev/null 2>&1
check "--spec with --no-spec exits 1" 1 $?

echo ""
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
