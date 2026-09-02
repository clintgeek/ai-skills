#!/usr/bin/env bash
# Repo-wide invariants: things true of EVERY tracked file, not of one component.
#
# These lived as inline steps in .github/workflows/tests.yml, which meant they
# only ran after a push. Two CI failures today were in inline steps duplicating a
# suite check I had already fixed locally — a check you cannot run before pushing
# is a slow way to learn something a suite would have told you in a second.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/assert.sh"
cd "$REPO_ROOT"

echo "== every tracked shell script parses =="
# POSIX files are checked with dash (strictest commonly available), not bash -n:
# bash accepts [[ ]], arrays and local, so bash -n on a #!/bin/sh file proves
# nothing about whether it runs where it has to.
posix_fail="" bash_fail="" zsh_fail=""
read_lines_into SH_FILES < <(git ls-files '*.sh')
read_lines_into ZSH_FILES < <(git ls-files '*.zsh')
read_lines_into EXTLESS < <(git ls-files 'skills/*/scripts/*' | grep -v '\.')

assert "found shell files to check (${#SH_FILES[@]} .sh, ${#EXTLESS[@]} extensionless)" \
  $([[ ${#SH_FILES[@]} -ge 5 ]] && echo 0 || echo 1)

for f in ${SH_FILES[@]+"${SH_FILES[@]}"} ${EXTLESS[@]+"${EXTLESS[@]}"}; do
  [[ -f "$f" ]] || continue
  if head -1 "$f" | grep -q '^#!/bin/sh'; then
    if command -v dash >/dev/null 2>&1; then
      dash -n "$f" 2>/dev/null || posix_fail="$posix_fail $f"
    else
      /bin/sh -n "$f" 2>/dev/null || posix_fail="$posix_fail $f"
    fi
  else
    bash -n "$f" 2>/dev/null || bash_fail="$bash_fail $f"
  fi
done
for f in ${ZSH_FILES[@]+"${ZSH_FILES[@]}"}; do
  zsh -n "$f" 2>/dev/null || zsh_fail="$zsh_fail $f"
done
check "every POSIX sh file parses strictly" "" "$posix_fail"
check "every bash file parses"              "" "$bash_fail"
check "every zsh file parses"               "" "$zsh_fail"

# Control: the checker must actually reject broken syntax, or the three above
# are green on an empty list.
BROKEN="$(mktemp)"; printf 'if [ x = x ; then :\n' > "$BROKEN"
bash -n "$BROKEN" 2>/dev/null
assert "  (control) the syntax check rejects a broken file" $([[ $? -ne 0 ]] && echo 0 || echo 1)
rm -f "$BROKEN"

echo "== every skill is loadable =="
# A skill with no SKILL.md, or one missing frontmatter, is invisible to every
# tool wired to this repo — and silently so.
missing=""
read_lines_into SKILL_DIRS < <(find skills -maxdepth 1 -mindepth 1 -type d | sort)
assert "found skills to check (${#SKILL_DIRS[@]})" $([[ ${#SKILL_DIRS[@]} -ge 4 ]] && echo 0 || echo 1)
for d in ${SKILL_DIRS[@]+"${SKILL_DIRS[@]}"}; do
  f="$d/SKILL.md"
  [[ -f "$f" ]]                        || { missing="$missing $d:no-SKILL.md"; continue; }
  head -1 "$f" | grep -qx -- '---'     || missing="$missing $(basename "$d"):no-frontmatter"
  grep -qm1 '^name:' "$f"              || missing="$missing $(basename "$d"):no-name"
  grep -qm1 '^description:' "$f"       || missing="$missing $(basename "$d"):no-description"
done
check "every skill has SKILL.md with name and description" "" "$missing"

# The name in the frontmatter must match the directory, or the skill loads under
# a name nothing references.
mismatched=""
for d in ${SKILL_DIRS[@]+"${SKILL_DIRS[@]}"}; do
  f="$d/SKILL.md"; [[ -f "$f" ]] || continue
  declared="$(awk 'NR>1 && /^name:/{print $2; exit}' "$f")"
  [[ "$declared" == "$(basename "$d")" ]] || mismatched="$mismatched $(basename "$d")!=$declared"
done
check "each skill's declared name matches its directory" "" "$mismatched"

echo "== the skills are reachable through the hotwired path =="
# The reorg broke exactly this: tools were linked one level too high, so every
# skill in this repo was invisible and nothing noticed.
for d in ${SKILL_DIRS[@]+"${SKILL_DIRS[@]}"}; do
  assert "  skills/$(basename "$d")/SKILL.md is where a tool would look for it" \
    $([[ -f "$REPO_ROOT/skills/$(basename "$d")/SKILL.md" ]] && echo 0 || echo 1)
done

report_and_exit
