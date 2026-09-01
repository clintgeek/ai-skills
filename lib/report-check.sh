#!/usr/bin/env bash
# Validate that a challenger actually produced a review.
#
# ai-battle printed "Battle complete" over a 0-byte file twice, and over a
# report truncated at finding 8 of 18 claimed. A tool that cannot tell a review
# from silence is worse than no tool: it reports success and the human believes
# the code was inspected.
#
# Source it; it runs nothing on its own:
#   source lib/report-check.sh
#   validate_report <report-file> [stderr-file]
#
# Exit codes (also used as battle_runner's exit code):
#   0  looks like a real review
#   4  no review: empty, trivial, or the challenger was blocked
# A suspected TRUNCATION is reported loudly but still exits 0 -- the findings
# that did arrive are real and worth reading, and the count parsing is a
# heuristic that must not be able to discard a genuine report.

REPORT_MIN_BYTES="${REPORT_MIN_BYTES:-200}"

# Signatures of a challenger that launched but could not work. These are real
# strings observed from devin and agy in headless runs; a permission refusal is
# not a clean review and must never be reported as one.
_report_blocked_patterns=(
  'rejected a tool call'
  'no output produced'
  'cannot prompt'
  'auto-denied'
  'requires confirmation'
  'permission that headless mode'
)

# rc 0 if the file carries the severity structure the prompt demands.
_report_has_structure() {
  grep -qE '\[?(P0|P1|P2)[/ ]|CRITICAL|WARNING|SPECULATIVE' "$1" 2>/dev/null
}

# Claimed vs delivered finding counts, for truncation detection. Prints
# "<claimed> <delivered>"; claimed is 0 when no summary was found.
_report_counts() {
  local file="$1" claimed=0 delivered=0 n
  for n in $(grep -oE '\[?(P0|P1|P2)[^0-9]{0,24}([0-9]+)' "$file" 2>/dev/null \
             | grep -oE '[0-9]+$'); do
    claimed=$((claimed + n))
  done
  delivered="$(grep -cE '^#{2,4} *([0-9]+\.|\[?(P0|P1|P2))' "$file" 2>/dev/null || true)"
  echo "$claimed $delivered"
}

validate_report() {
  local file="${1:-}" errfile="${2:-}"
  local size=0 blocked="" pat

  if [[ -z "$file" ]] || [[ ! -f "$file" ]]; then
    echo "Error: no report file was produced ($file). The challenger did not run." >&2
    return 4
  fi
  size="$(wc -c < "$file" | tr -d ' ')"

  # Whatever else is true, a blocked challenger did not review anything. Check
  # both streams: the refusal may land on either.
  for pat in "${_report_blocked_patterns[@]}"; do
    if grep -qiF "$pat" "$file" 2>/dev/null; then blocked="$pat"; break; fi
    if [[ -n "$errfile" && -f "$errfile" ]] && grep -qiF "$pat" "$errfile" 2>/dev/null; then
      blocked="$pat"; break
    fi
  done
  if [[ -n "$blocked" ]]; then
    echo "Error: the challenger was BLOCKED, not satisfied — it never reviewed the diff." >&2
    echo "  signature: \"$blocked\"" >&2
    echo "  This is a permission/headless problem, not a clean bill of health." >&2
    echo "  Report ($size bytes): $file" >&2
    [[ -n "$errfile" && -f "$errfile" ]] && echo "  Stderr: $errfile" >&2
    return 4
  fi

  if [[ "$size" -eq 0 ]]; then
    echo "Error: the challenger produced an EMPTY report ($file)." >&2
    echo "  Nothing was reviewed. Do not read this as 'no findings'." >&2
    [[ -n "$errfile" && -f "$errfile" ]] && echo "  Stderr may say why: $errfile" >&2
    return 4
  fi

  if [[ "$size" -lt "$REPORT_MIN_BYTES" ]]; then
    echo "Error: the report is only $size bytes — too short to be a review." >&2
    echo "  First line: $(head -1 "$file")" >&2
    echo "  Full file: $file" >&2
    return 4
  fi

  if ! _report_has_structure "$file"; then
    echo "Error: the report has no severity findings (no P0/P1/P2, CRITICAL/WARNING/SPECULATIVE)." >&2
    echo "  The challenger produced $size bytes of something, but not the review that was asked for." >&2
    echo "  Full file: $file" >&2
    return 4
  fi

  # Truncation: a summary promising more findings than the body delivers. Warn
  # only — what arrived is real, and this parse is a heuristic.
  local counts claimed delivered
  counts="$(_report_counts "$file")"
  claimed="${counts%% *}"
  delivered="${counts##* }"
  if [[ "$claimed" -gt 0 && "$delivered" -gt 0 && "$delivered" -lt "$claimed" ]]; then
    echo "Warning: the report looks TRUNCATED — its summary claims $claimed findings but only $delivered are written out." >&2
    echo "  Treat the missing $((claimed - delivered)) as unreviewed, not as absent." >&2
  fi
  return 0
}
