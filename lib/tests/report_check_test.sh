#!/usr/bin/env bash
# Tests for lib/report-check.sh — the guard that stops ai-battle reporting a
# review that never happened.
#
# This exists because the runner printed "✅ Battle complete" over a 0-byte
# report twice, and over a report truncated at 8 of 18 claimed findings. The
# distinction that matters: "no findings" and "no review" look identical to a
# human skimming output, and only one of them is good news.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../report-check.sh"

PASS=0 FAIL=0
check() { if [[ "$2" == "$3" ]]; then PASS=$((PASS+1)); echo "  ok: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected rc $2, got $3)" >&2; fi }
assert() { if [[ "$2" -eq 0 ]]; then PASS=$((PASS+1)); echo "  ok: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1" >&2; fi }

W="$(mktemp -d "${TMPDIR:-/tmp}/report_check_test.XXXXXX")"
trap 'rm -rf "$W"' EXIT INT TERM

# A report that genuinely looks like a review.
cat > "$W/good.md" <<'EOF'
# Scorecard
**[P0/CRITICAL]: 1 · [P1/WARNING]: 2 · [P2/SPECULATIVE]: 0**

### 1. Broken thing `[P0]`
- **Location:** `lib/x.sh:10`
- **Attack scenario:** it explodes on retry
### 2. Second thing `[P1]`
- **Location:** `lib/y.sh:20`
### 3. Third thing `[P1]`
- **Location:** `lib/z.sh:30`
EOF

echo "== a real review passes =="
validate_report "$W/good.md" >/dev/null 2>&1;  check "a structured report exits 0" 0 $?

echo "== no review must never pass =="
: > "$W/empty.md"
validate_report "$W/empty.md" >/dev/null 2>&1; check "an empty report exits 4" 4 $?
out="$(validate_report "$W/empty.md" 2>&1)"
assert "  and says it is not 'no findings'" $(grep -q "not to read this as\|Do not read this as" <<<"$out" || grep -q "no findings" <<<"$out" && echo 0 || echo 1)

validate_report "$W/missing.md" >/dev/null 2>&1; check "a missing report exits 4" 4 $?

# The exact 113-byte bail devin produced.
printf "I'll conduct the adversarial review. Let me first ground myself in the actual working tree and the target files.\n" > "$W/bail.md"
validate_report "$W/bail.md" >/dev/null 2>&1; check "the real 113-byte devin bail exits 4" 4 $?

# Long, but no findings — prose is not a review.
head -c 400 /dev/zero | tr '\0' 'x' > "$W/prose.md"
validate_report "$W/prose.md" >/dev/null 2>&1; check "long prose with no severity findings exits 4" 4 $?

echo "== a blocked challenger is not a clean bill of health =="
# Observed strings from devin and agy in headless runs.
for sig in "rejected a tool call that requires confirmation" \
           "no output produced — a tool required the \"command\" permission" \
           "permission that headless mode cannot prompt for"; do
  printf '%s\n' "$sig" > "$W/err.log"
  validate_report "$W/good.md" "$W/err.log" >/dev/null 2>&1
  check "blocked via stderr: '${sig:0:34}...' exits 4" 4 $?
done
# Even a well-formed report is rejected if the challenger was blocked: the
# structure could be an echo of the prompt rather than a real review.
out="$(validate_report "$W/good.md" "$W/err.log" 2>&1)"
assert "  and the message names the signature" $(grep -q 'signature:' <<<"$out" && echo 0 || echo 1)
assert "  and says it is a permission problem" $(grep -qi 'permission/headless problem' <<<"$out" && echo 0 || echo 1)
# A blocked signature in the report body itself must also be caught.
cp "$W/good.md" "$W/blocked-body.md"
echo "warning: rejected a tool call that requires confirmation" >> "$W/blocked-body.md"
validate_report "$W/blocked-body.md" >/dev/null 2>&1; check "blocked via the report body exits 4" 4 $?

echo "== truncation warns but does not discard =="
# The summary promises 18; only three findings are written out. What arrived is
# real, so this must stay exit 0 — the count parse is a heuristic and must not
# be able to throw away a genuine report.
cat > "$W/trunc.md" <<'EOF'
[P0/CRITICAL]: 1
[P1/WARNING]: 9
[P2/SPECULATIVE]: 8

### 1. First `[P0]`
- **Location:** `a.sh:1`
### 2. Second `[P1]`
- **Location:** `b.sh:2`
### 3. Third `[P1]`
- **Location:** `c.sh:3`
- **Attack scenario:** padding so this fixture clears REPORT_MIN_BYTES and
  actually exercises the truncation path rather than the size floor. A report
  this shape is what devin produced: a real summary, a real prefix of findings,
  and then nothing.
EOF
size=$(wc -c < "$W/trunc.md" | tr -d ' ')
assert "the truncation fixture clears the size floor (${size}b >= ${REPORT_MIN_BYTES}b)" \
  $([[ "$size" -ge "$REPORT_MIN_BYTES" ]] && echo 0 || echo 1)
validate_report "$W/trunc.md" >/dev/null 2>&1; check "a truncated report still exits 0" 0 $?
out="$(validate_report "$W/trunc.md" 2>&1)"
assert "  but warns about truncation" $(grep -qi 'TRUNCATED' <<<"$out" && echo 0 || echo 1)
assert "  and says the missing ones are unreviewed, not absent" \
  $(grep -qi 'unreviewed, not as absent' <<<"$out" && echo 0 || echo 1)
# A complete report must NOT be flagged.
out="$(validate_report "$W/good.md" 2>&1)"
assert "a complete report is not flagged as truncated" $(! grep -qi 'TRUNCATED' <<<"$out" && echo 0 || echo 1)

echo "== the runner wires it in =="
BR="$SCRIPT_DIR/../../skills/ai-battle/scripts/battle_runner.sh"
grep -q 'source .*lib/report-check.sh' "$BR"; assert "battle_runner sources the checker" $?
grep -q 'if ! validate_report' "$BR";          assert "  and gates its success banner on it" $?
grep -q 'NO REVIEW PRODUCED' "$BR";            assert "  with an unmistakable failure banner" $?
grep -q 'exit 4' "$BR";                        assert "  and exits 4" $?
# The success banner must come AFTER the check, or it still lies.
# Anchor on the echo, not the word: the explanatory comment above the check also
# contains "Battle complete" and matching it inverted the comparison.
vline=$(grep -n 'if ! validate_report' "$BR" | head -1 | cut -d: -f1)
sline=$(grep -nE '^\s*echo ".*Battle complete' "$BR" | head -1 | cut -d: -f1)
assert "the success banner is printed after validation ($vline < $sline)" \
  $([[ "$vline" -lt "$sline" ]] && echo 0 || echo 1)

echo ""
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
