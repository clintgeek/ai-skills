#!/usr/bin/env bash
# Shared assertion helpers for the test suites.
#
# WHY THIS EXISTS
# ---------------
# Across one working session I wrote NINE assertions that could not fail. Not
# nine unrelated slips -- one habit, in several disguises:
#
#   1. `assert "... $(readlink x) ..." $?`   -- the command substitution in the
#      DESCRIPTION runs first and overwrites $?, so the assertion reads its own
#      success. Argument expansion is left-to-right.
#   2. `grep -q 'readlink -f' file`          -- matched the COMMENT explaining
#      that the file avoids readlink -f.
#   3. `grep -rl 'tool_roster()' ...`        -- matched the test's own pattern
#      string, and a mention in a comment.
#   4. `BS_BASH=''; bs_exec_bash ...`        -- the function re-resolves BS_BASH
#      on entry, so presetting it proved nothing and the guard was unreachable.
#   5. `[[ /usr/local != $prefix ]]`         -- true on arm64, false on Linux,
#      where /usr/local IS the prefix.
#   6. `mapfile -t ARR < <(...)`             -- bash 4+; under macOS system bash
#      the array is empty and the whole loop is silently skipped.
#
# The shape is always the same: reaching for a concrete value from the machine in
# front of me when the assertion needed a RELATION (different-from, below-root,
# not-the-current-shell, defined-before-sourcing).
#
# So: capture status BEFORE building any message, and pair every guard with a
# CONTROL that proves the guard can still fail.
#
#   check_control "<desc>" <pass-rc> <control-rc>
#
# fails when the control ALSO passes, because a check that cannot distinguish
# its two cases is not a check.

PASS=0
FAIL=0

_assert_pass() { PASS=$((PASS + 1)); echo "  ok: $1"; }
_assert_fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }

# assert <description> <rc>   -- rc 0 means pass.
# ALWAYS capture rc into a variable first:
#     do_thing; rc=$?
#     desc="$(build_description)"
#     assert "$desc" "$rc"
assert() {
  if [ "${2:-1}" -eq 0 ]; then _assert_pass "$1"; else _assert_fail "$1"; fi
}

# check <description> <expected> <actual>
check() {
  if [ "$2" = "$3" ]; then _assert_pass "$1"; else _assert_fail "$1 (expected '$2', got '$3')"; fi
}

# check_control <description> <rc-of-the-real-case> <rc-of-the-control-case>
#
# The real case must pass AND the control must fail. If both pass, the check
# cannot tell them apart and is reported as broken rather than green.
check_control() {
  local desc="$1" real="${2:-1}" control="${3:-0}"
  if [ "$real" -ne 0 ]; then
    _assert_fail "$desc (the case that should PASS did not)"
    return
  fi
  if [ "$control" -eq 0 ]; then
    _assert_fail "$desc — UNFALSIFIABLE: the control passed too, so this check cannot fail"
    return
  fi
  _assert_pass "$desc (control confirms it can fail)"
}

# Print the CODE of a shell file: comments and single-quoted spans removed.
# Searching a file for a construct it documents avoiding otherwise matches the
# documentation. See disguises 2 and 3 above.
code_of() { sed -e 's/[[:space:]]*#.*$//' -e "s/'[^']*'/''/g" "$1"; }

# Read lines into an array without mapfile, which is bash 4+ and silently
# yields an EMPTY array under macOS's bash 3.2 -- skipping whatever loop
# depended on it. See disguise 6.
#   read_lines_into ARRAYNAME < <(producer)
read_lines_into() {
  local __name="$1" __line
  eval "$__name=()"
  while IFS= read -r __line; do
    [ -n "$__line" ] || continue
    eval "$__name+=(\"\$__line\")"
  done
}

report_and_exit() {
  echo ""
  echo "$PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ]
}
