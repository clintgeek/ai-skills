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
BR="$SCRIPT_DIR/../../ai-battle/scripts/battle_runner.sh"

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
"$SB" ensure >/dev/null 2>&1;                     check "ensure scaffolds a DRAFT and exits 3" 3 $?
grep -q "Status: DRAFT" TICKET-SPEC.md;           assert "scaffold carries the DRAFT banner" $?
grep -q "TEST-1" TICKET-SPEC.md;                  assert "scaffold collected ticket-id evidence" $?
"$SB" build >/dev/null 2>&1;                      check "build refuses to overwrite without --force" 1 $?

echo "== F1: stale draft must not satisfy ensure =="
"$SB" ensure >/dev/null 2>&1;                     check "ensure on an existing unfilled DRAFT exits 3" 3 $?
bash -c "source '$SB'
SPEC_INTENT='Test intent.'
SPEC_REQUIREMENTS='1. Testable requirement.'
build_spec_scaffold TICKET-SPEC.md HEAD~1..HEAD '' true"
"$SB" ensure >/dev/null 2>&1;                     check "ensure on a completed spec exits 0" 0 $?
bash -c "source '$SB'; spec_is_draft TICKET-SPEC.md"
check "completed spec has no DRAFT banner" 1 $?

echo "== F2: spec-less dry-run refuses without --no-spec =="
rm TICKET-SPEC.md
CALLING_AGENT=devin "$BR" --dry-run >/dev/null 2>&1
check "spec-less --dry-run exits 3" 3 $?
[[ ! -e TICKET-SPEC.md ]];                        assert "spec-less --dry-run writes nothing" $?
CALLING_AGENT=devin "$BR" --dry-run --no-spec >/dev/null 2>&1
check "spec-less --dry-run with --no-spec exits 0" 0 $?

echo "== F3: spec scaffolds before challenger selection =="
# Strip AI CLIs from PATH; keep system tools so git/grep still work.
NO_AI_PATH="/usr/bin:/bin"
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
