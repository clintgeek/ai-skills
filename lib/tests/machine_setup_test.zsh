#!/usr/bin/env zsh
# Regression tests for machine-setup: the app catalog, role/category selection,
# extras classification, and the interactive checklist.
# Run: ~/.ai/lib/tests/machine_setup_test.zsh   (exit 0 = all pass)
#
# Covers the three findings from the 2026-09-01 review:
#   P1-3: --role admin / --role general selected nothing but `base`, and the
#         spec's design/data/writing/gaming roles were hard-rejected
#   P1-4: single-token --extras were silently dropped; raw commands containing
#         a comma were split into separate eval'd fragments
#   P1-5: the checklist could only remove, by number, with no add or un-remove
setopt no_unset pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h}"
WIZ="$REPO_ROOT/skills/machine-setup/scripts/machine-wizard.zsh"

PASS=0 FAIL=0
check() { # check <desc> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    (( PASS++ )); echo "  ok: $1"
  else
    (( FAIL++ )); echo "  FAIL: $1 (expected '$2', got '$3')" >&2
  fi
}
assert() { # assert <desc> <rc>
  if (( $2 == 0 )); then
    (( PASS++ )); echo "  ok: $1"
  else
    (( FAIL++ )); echo "  FAIL: $1" >&2
  fi
}

# Load the libs directly for unit-level checks.
REPO_ROOT="$REPO_ROOT" source "$REPO_ROOT/lib/machine-setup.zsh"

# Run the wizard in dry-run and print its plan.
plan() { "$WIZ" --dry-run "$@" < /dev/null 2>&1 }
# Count "install" lines in a plan.
plan_count() { plan "$@" | grep -c '^  install ' }

echo "== catalog integrity =="
missing=()
for a in "${APPS[@]}"; do
  [[ -n "${APP_NAME[$a]:-}" ]] || missing+=("$a name")
  [[ -n "${APP_TAGS[$a]:-}" ]] || missing+=("$a tags")
done
check "every app has a name and tags" "" "${missing[*]}"

# An app reachable by no role and no category, and not in base, is dead weight.
orphans=()
for a in "${APPS[@]}"; do
  [[ -n "${APP_ROLES[$a]:-}" ]] && continue
  [[ "${APP_TAGS[$a]}" == *base* ]] && continue
  orphans+=("$a")
done
check "no app is unreachable by every role" "" "${orphans[*]}"

# Roles and categories must not overlap -- conflating them is what made
# `--role dev` and `--categories dev` identical.
overlap=()
for a in "${APPS[@]}"; do
  for r in ${(s:,:)APP_ROLES[$a]:-}; do
    for t in ${(s:,:)APP_TAGS[$a]:-}; do
      [[ "$r" == "$t" ]] && overlap+=("$a:$r")
    done
  done
done
check "role names never appear as category tags" "" "${overlap[*]}"

echo "== set -e safety =="
# `(( n++ ))` evaluates to the PRE-increment value, so the first increment from
# 0 returns 0 -- a non-zero exit status -- and silently aborts the script under
# `set -e`. This shipped once and was invisible: the checklist just stopped
# printing mid-list and two tests passed for the wrong reason. Ban the form.
badinc=()
for f in "$REPO_ROOT/lib/machine-setup.zsh" "$REPO_ROOT/lib/app-catalog.zsh" \
         "$REPO_ROOT/skills/machine-setup/scripts/machine-wizard.zsh"; do
  # Strip comments first -- the fixes are documented with the very form being
  # banned, and matching the explanation instead of the code is a false alarm.
  sed -e 's/[[:space:]]*#.*$//' "$f" \
    | grep -qE '\(\([^)]*(\+\+|--)[^)]*\)\)' && badinc+=("${f:t}")
done
check "no bare (( x++ )) in set -e code paths" "" "${badinc[*]}"
# And prove the wizard really does survive counting from zero.
out="$(plan --role dev --categories cli)"
assert "the plan runs to completion under set -e" $(grep -q 'Dry run, not executing' <<<"$out" && echo 0 || echo 1)

echo "== P1-3: every valid role selects real apps =="
VALID_ROLES=(dev design data writing gaming admin general)
for r in "${VALID_ROLES[@]}"; do
  n="$(role_app_count "$r")"
  assert "role '$r' has catalog apps ($n)" $(( n > 0 ? 0 : 1 ))
done

# The original defect: base-only selection for admin/general.
preselect_apps "" ""
base_n=${#SELECTED_APPS[@]}
for r in "${VALID_ROLES[@]}"; do
  preselect_apps "$r" ""
  assert "role '$r' selects more than the base set (${#SELECTED_APPS[@]} > $base_n)" \
    $(( ${#SELECTED_APPS[@]} > base_n ? 0 : 1 ))
done

# admin and general must no longer be indistinguishable from each other.
preselect_apps admin ""; admin_sel="${(j: :)${(o)SELECTED_APPS}}"
preselect_apps general ""; general_sel="${(j: :)${(o)SELECTED_APPS}}"
assert "admin and general select different sets" $([[ "$admin_sel" != "$general_sel" ]] && echo 0 || echo 1)

echo "== multiple roles =="
preselect_apps dev ""; dev_n=${#SELECTED_APPS[@]}
preselect_apps gaming ""; gaming_n=${#SELECTED_APPS[@]}
preselect_apps "dev,gaming" ""; both_n=${#SELECTED_APPS[@]}
assert "dev,gaming is a union, not a replacement ($both_n > $dev_n)" $(( both_n > dev_n ? 0 : 1 ))
assert "  and no app is duplicated" $([[ "$both_n" -eq "${#${(u)SELECTED_APPS[@]}}" ]] && echo 0 || echo 1)

echo "== spec roles are accepted, junk is rejected =="
for r in dev design data writing gaming admin general; do
  plan --role "$r" --categories cli >/dev/null 2>&1
  assert "--role $r is accepted" $?
done
# NOTE: capture then grep. Piping the wizard straight into grep under
# `pipefail` yields the wizard's exit status, so a correct rejection (exit 1)
# would read as a failed assertion.
out="$(plan --role bogus --categories cli || true)"
assert "--role bogus is rejected with a clear error" $(grep -q 'unknown role' <<<"$out" && echo 0 || echo 1)
assert "  and lists the valid roles" $(grep -q 'Valid roles:' <<<"$out" && echo 0 || echo 1)
out="$(plan --role dev --categories nonsense || true)"
assert "--categories nonsense is rejected with a clear error" $(grep -q 'unknown categor' <<<"$out" && echo 0 || echo 1)

echo "== P1-4: extras are never silently dropped =="
check "a known app id classifies as an app"      "app:git"     "$(classify_extra git)"
check "an unknown single token becomes a package" "pkg:neovim" "$(classify_extra neovim)"
check "a command with a space becomes a command"  "cmd:brew install x" "$(classify_extra 'brew install x')"
check "a path becomes a command"                  "cmd:./install.sh"   "$(classify_extra ./install.sh)"

# The original defect: `--extras neovim` printed "skip neovim (no mac installer)".
out="$(plan --role dev --categories cli --extras neovim)"
assert "single-token extra is planned, not skipped" $(grep -q 'install neovim (package)' <<<"$out" && echo 0 || echo 1)
# [a-z-]+ not \w+: the package manager may be `apt-get`, and \w excludes the hyphen.
assert "  and gets a real install command" $(grep -qE 'install neovim \(package\): (brew install|sudo [a-z-]+ install|sudo pacman|sudo apk)' <<<"$out" && echo 0 || echo 1)

# The original defect: a comma inside a raw command split it into two evals.
RAW='brew tap a/b, brew install c'
out="$(plan --role dev --categories cli --extra-cmd "$RAW")"
assert "--extra-cmd keeps a comma-containing command intact" $(grep -qF "install $RAW: $RAW" <<<"$out" && echo 0 || echo 1)
check "  and produces exactly one command line for it" 1 "$(grep -cF "$RAW" <<<"$out")"

# A comma'd command via --extras is ambiguous (comma is the list separator).
# It must be refused outright, never split into separately-eval'd fragments.
out="$(plan --role dev --categories cli --extras "$RAW" || true)"
assert "a comma'd command via --extras is refused, not split" $(grep -q 'cannot appear inside one entry' <<<"$out" && echo 0 || echo 1)
assert "  and the error points at --extra-cmd" $(grep -q -- '--extra-cmd' <<<"$out" && echo 0 || echo 1)
assert "  and no fragment is planned" $(! grep -q '^  install brew tap' <<<"$out" && echo 0 || echo 1)
# A single command with no comma is still fine through --extras.
out="$(plan --role dev --categories cli --extras 'brew install oneoff')"
check "a comma-free command via --extras is kept whole" 1 "$(grep -cF 'brew install oneoff' <<<"$out")"

echo "== --extras is repeatable and additive =="
out="$(plan --role dev --categories cli --extras neovim --extras htop --extra-cmd 'echo one' --extra-cmd 'echo two')"
assert "first --extras survives"  $(grep -q 'neovim (package)' <<<"$out" && echo 0 || echo 1)
assert "second --extras survives" $(grep -q 'install htop'     <<<"$out" && echo 0 || echo 1)
assert "first --extra-cmd survives"  $(grep -q 'echo one' <<<"$out" && echo 0 || echo 1)
assert "second --extra-cmd survives" $(grep -q 'echo two' <<<"$out" && echo 0 || echo 1)

# An extra already in the preselected set must not appear twice.
out="$(plan --role dev --categories cli --extras git)"
check "an extra already selected is not duplicated" 1 "$(grep -c 'install Git:' <<<"$out")"

echo "== typed items produce the right commands =="
OS_KIND=mac PKG_MGR=brew
check "app item -> catalog command"  "brew install git"   "$(item_install_cmd app:git)"
check "pkg item -> package command"  "brew install nvim"  "$(item_install_cmd pkg:nvim)"
check "cmd item -> verbatim"         "make && make check" "$(item_install_cmd 'cmd:make && make check')"
check "app label uses the catalog name" "Visual Studio Code" "$(item_label app:visual-studio-code)"
check "pkg label is marked as a package" "nvim (package)"     "$(item_label pkg:nvim)"

echo "== P1-5: interactive checklist can toggle and add =="
# Drive the real interactive loop over a plain pipe via the documented seam.
# A pty (script(1)) drops input lines nondeterministically, which made these
# tests flaky rather than meaningful.
run_tty() { # run_tty <input-lines>
  printf '%s' "$1" | MACHINE_WIZARD_FORCE_INTERACTIVE=1 \
    "$WIZ" --dry-run --role dev --categories cli 2>&1
}
if true; then
  # Toggle item 1 off, then finish: it must vanish from the plan.
  base_plan="$(plan --role dev --categories cli)"
  first_label="$(sed -n 's/^  install \([^:]*\):.*/\1/p' <<<"$base_plan" | head -1)"
  out="$(run_tty $'1\ndone\n')"
  assert "toggling item 1 off removes it from the plan ($first_label)" \
    $(! grep -q "^  install $first_label:" <<<"$out" && echo 0 || echo 1)

  # Toggle off then on again -- the un-remove the old code could not do.
  out="$(run_tty $'1\n1\ndone\n')"
  assert "toggling twice restores it (un-remove works)" \
    $(grep -q "install $first_label" <<<"$out" && echo 0 || echo 1)

  # Add a package name interactively.
  out="$(run_tty $'+neovim\ndone\n')"
  assert "'+neovim' adds a package interactively" \
    $(grep -q 'neovim (package)' <<<"$out" && echo 0 || echo 1)

  # Add a raw command interactively, comma and all.
  out="$(run_tty $'+brew tap a/b, brew install c\ndone\n')"
  assert "'+<command>' adds a raw command interactively" \
    $(grep -qF 'brew tap a/b, brew install c' <<<"$out" && echo 0 || echo 1)

  # none / all
  out="$(run_tty $'none\ndone\n')"
  assert "'none' deselects everything" $([[ "$(grep -c '^  install ' <<<"$out")" -eq 0 ]] && echo 0 || echo 1)
  out="$(run_tty $'none\nall\ndone\n')"
  assert "'all' reselects everything" $([[ "$(grep -c '^  install ' <<<"$out")" -gt 0 ]] && echo 0 || echo 1)

  # Junk must not crash or silently mutate the selection.
  out="$(run_tty $'999\ndone\n')"
  assert "an out-of-range number is reported, not applied" $(grep -q 'no item 999' <<<"$out" && echo 0 || echo 1)
  out="$(run_tty $'zzz\ndone\n')"
  assert "unrecognized input is reported" $(grep -q 'unrecognized' <<<"$out" && echo 0 || echo 1)
fi

echo "== non-interactive safety is unchanged =="
out="$(plan --repos-only)"
assert "--repos-only plans no app installs" $([[ "$(grep -c '^  install ' <<<"$out")" -eq 0 ]] && echo 0 || echo 1)
out="$("$WIZ" --role dev --categories cli < /dev/null 2>&1 || true)"
assert "non-interactive without --yes refuses to execute" $(grep -q 'run again with --yes' <<<"$out" && echo 0 || echo 1)
out="$(plan --repos-only --ai)"
assert "--ai with --repos-only warns that it is ignored" $(grep -q 'ignored with --repos-only' <<<"$out" && echo 0 || echo 1)

echo ""
echo "$PASS passed, $FAIL failed"
(( FAIL == 0 ))
