#!/usr/bin/env bash
# Tests for lib/bootstrap.sh -- the shared machine bootstrapper.
# Run: ~/.ai/lib/tests/bootstrap_test.sh   (exit 0 = all pass)
#
# bootstrap.sh must stay POSIX sh and must never mutate the machine without
# consent, so that is what these assert. The "nothing installed yet" paths are
# reached via the BS_*_SEARCH knobs rather than by breaking the host.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BS="$SCRIPT_DIR/../bootstrap.sh"

PASS=0 FAIL=0
check() { # check <description> <expected> <actual>
  if [[ "$2" == "$3" ]]; then
    PASS=$((PASS + 1)); echo "  ok: $1"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $1 (expected '$2', got '$3')" >&2
  fi
}
assert() { # assert <description> <condition-rc>
  if [[ "$2" -eq 0 ]]; then
    PASS=$((PASS + 1)); echo "  ok: $1"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2
  fi
}
# Run a snippet in a clean POSIX sh with bootstrap.sh sourced.
bs() { /bin/sh -c ". '$BS'; $1" 2>&1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bootstrap_test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM

echo "== POSIX purity =="
/bin/sh -n "$BS" >/dev/null 2>&1;   assert "parses as POSIX sh" $?
# The file installs the shells everything else needs, so it cannot use them.
# Strip comments, and strip lines handing a snippet to another shell via -c
# '...' (e.g. bash -c 'echo ${BASH_VERSINFO[0]}') -- that is foreign-shell code
# run BY that shell, deliberately, not sh code run by this file.
BS_CODE="$WORK/bootstrap.code.sh"
sed -e 's/[[:space:]]*#.*$//' "$BS" | grep -v -- "-c '" > "$BS_CODE"
! grep -nE '\[\[|declare -|typeset -|\bfunction \w+ *\(|\$\{[A-Za-z_]+\[|<<<|\$\(\(|echo -e' "$BS_CODE" >/dev/null
assert "contains no bash/zsh-only constructs" $?
! grep -n -F '+=' "$BS_CODE" >/dev/null
assert "uses no += array/string append" $?
# dash is the strictest POSIX sh commonly available; use it when present.
if command -v dash >/dev/null 2>&1; then
  dash -n "$BS" >/dev/null 2>&1; assert "parses under dash (strict POSIX)" $?
fi
grep -q '^#!/bin/sh' "$BS";         assert "declares #!/bin/sh" $?

echo "== detection =="
out="$(bs 'bs_detect_os; echo $BS_OS')"
case "$out" in mac|linux|windows) rc=0 ;; *) rc=1 ;; esac
assert "bs_detect_os returns a known OS (got '$out')" $rc

out="$(bs 'bs_detect_os; bs_detect_pkg_mgr; echo $BS_PKG_MGR')"
if [[ "$(uname -s)" == "Darwin" ]]; then
  # On a Mac WITH brew this must be "brew"; on a fresh Mac WITHOUT brew it must
  # be empty, because there is no other package manager and bs_ensure_brew is
  # what fixes that. Asserting "brew" unconditionally would fail on exactly the
  # machine this tool exists for.
  if command -v brew >/dev/null 2>&1; then
    check "macOS with brew resolves its package manager to brew" "brew" "$out"
  else
    check "macOS without brew reports no package manager" "" "$out"
    assert "  and bs_ensure_brew is the thing that would fix it" \
      $(bs 'BS_DRY_RUN=1; export BS_DRY_RUN; bs_ensure_brew' 2>&1 | grep -q 'brew' && echo 0 || echo 1)
  fi
else
  assert "linux found some package manager (got '$out')" $([[ -n "$out" ]] && echo 0 || echo 1)
fi

out="$(bs 'echo $(bs_brew_prefix)')"
case "$(uname -m)" in
  arm64) check "brew prefix on Apple Silicon" "/opt/homebrew" "$out" ;;
  *)     assert "brew prefix is a real path (got '$out')" $([[ -n "$out" ]] && echo 0 || echo 1) ;;
esac

echo "== bash >= 4 discovery =="
out="$(bs 'bs_find_bash')"
assert "finds a bash 4+ on this machine (got '$out')" $([[ -n "$out" ]] && echo 0 || echo 1)
maj="$("$out" -c 'echo ${BASH_VERSINFO[0]}')"
assert "the bash it found really is >= 4 (major $maj)" $([[ "$maj" -ge 4 ]] && echo 0 || echo 1)
# The old version of this test pointed the search at /bin/bash and relied on it
# being 3.2 -- true on macOS, false on Linux, where /bin/bash is 5.x and
# accepting it is correct. Use a stub that reports major version 3 so the
# rejection logic is exercised identically everywhere.
OLDBASH="$WORK/oldbash"
mkdir -p "$OLDBASH"
cat > "$OLDBASH/bash" <<'STUB'
#!/bin/sh
# Pretends to be bash 3.2 for the one query bs_find_bash makes.
case "$2" in
  *BASH_VERSINFO*) echo 3 ;;
  *BASH_VERSION*)  echo "3.2.57(1)-release" ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$OLDBASH/bash"
bs "BS_BASH_SEARCH='$OLDBASH/bash'; export BS_BASH_SEARCH; PATH='$OLDBASH'; bs_find_bash" >/dev/null 2>&1
assert "rejects a bash reporting major version 3" $([[ $? -ne 0 ]] && echo 0 || echo 1)
# Guard the guard: the same stub reporting 5 must be ACCEPTED, or the test above
# would pass even if bs_find_bash rejected everything.
sed 's/echo 3 ;;/echo 5 ;;/' "$OLDBASH/bash" > "$OLDBASH/newbash"
chmod +x "$OLDBASH/newbash"
out="$(bs "BS_BASH_SEARCH='$OLDBASH/newbash'; export BS_BASH_SEARCH; PATH='$OLDBASH'; bs_find_bash")"
assert "  (control) accepts a bash reporting major version 5" $([[ -n "$out" ]] && echo 0 || echo 1)

echo "== sudo escalation fails fast rather than hanging =="
# Passwordless sudo (the usual VPS setup) just works. The gap was a box that
# PROMPTS, run unattended: plain `sudo` blocks on stdin nobody can answer, and it
# failed LATE -- after the plan was confirmed and packages were half installed.
if [[ "$(id -u)" == "0" ]]; then
  out="$(bs 'echo "BS_SUDO=[$BS_SUDO]"' < /dev/null)"
  assert "as root, no escalation prefix at all" \
    $(grep -q 'BS_SUDO=\[\]' <<<"$out" && echo 0 || echo 1)
else
  out="$(bs 'echo "BS_SUDO=$BS_SUDO"' < /dev/null)"
  assert "with no terminal, escalation uses sudo -n (fail fast)" \
    $(grep -q 'BS_SUDO=sudo -n' <<<"$out" && echo 0 || echo 1)
  # A freshly provisioned VPS drops you in as root, often on an image with no
  # `sudo` installed. Prefixing it there fails for no reason.
  # NOT via bs(): that sources bootstrap.sh before running the snippet, so
  # BS_SUDO is already computed by then. The stub has to precede the source.
  out="$(/bin/sh -c "id() { echo 0; }; . '$BS'; echo \"BS_SUDO=[\$BS_SUDO]\"" < /dev/null 2>&1)"
  assert "  and as root it is empty, not 'sudo'" \
    $(grep -q 'BS_SUDO=\[\]' <<<"$out" && echo 0 || echo 1)
fi
# Empty must expand to NOTHING, not to an empty argv slot.
out="$(/bin/sh -c 'BS_SUDO=""; set -- $BS_SUDO apt-get install -y zsh; echo "argc=$#"')"
assert "  an empty prefix leaves argv unchanged" $(grep -q 'argc=4' <<<"$out" && echo 0 || echo 1)
# Every escalation must route through BS_SUDO, or one call site can still hang.
! sed -e 's/[[:space:]]*#.*$//' "$BS" | grep -nE '(bs_run|bs_run_sh ")[^|]*\bsudo\b' | grep -qv 'BS_SUDO'
assert "  and every escalation routes through it" $?

# The preflight is advisory: a machine that already has brew, zsh and bash 4
# needs no root at all, and refusing there would be wrong.
out="$(bs 'bs_detect_os; bs_detect_pkg_mgr; bs_check_sudo; echo rc=$?' < /dev/null)"
if [[ "$(id -u)" == "0" ]] || sudo -n true 2>/dev/null; then
  assert "root or passwordless sudo passes the preflight" $(grep -q 'rc=0' <<<"$out" && echo 0 || echo 1)
else
  assert "password-required sudo + no terminal warns up front" \
    $(grep -q 'rc=1' <<<"$out" && echo 0 || echo 1)
  assert "  naming the steps that will fail" \
    $(grep -q 'package installs, chsh, /etc/shells' <<<"$out" && echo 0 || echo 1)
  assert "  and suggesting a way forward" \
    $(grep -qi 'passwordless sudo' <<<"$out" && echo 0 || echo 1)
fi
# It must NOT abort the bootstrap; plenty of runs need no root.
out="$(bs 'BS_DRY_RUN=1; export BS_DRY_RUN; bs_bootstrap; echo rc=$?' < /dev/null)"
assert "a failed sudo preflight does not abort the bootstrap" \
  $(grep -q 'rc=0' <<<"$out" && echo 0 || echo 1)

echo "== consent: nothing mutates without --yes =="
# Non-interactive, no BS_ASSUME_YES, no BS_DRY_RUN: must decline, not act.
out="$(bs 'bs_confirm "install something?"; echo "rc=$?"' < /dev/null)"
assert "bs_confirm refuses non-interactively without --yes" $(grep -q 'rc=1' <<<"$out" && echo 0 || echo 1)
assert "  and says why" $(grep -q 'non-interactive and no --yes' <<<"$out" && echo 0 || echo 1)
out="$(bs 'BS_ASSUME_YES=1; export BS_ASSUME_YES; bs_confirm "x"; echo "rc=$?"' < /dev/null)"
assert "bs_confirm accepts with BS_ASSUME_YES" $(grep -q 'rc=0' <<<"$out" && echo 0 || echo 1)

echo "== dry run never executes =="
CANARY="$WORK/canary"
bs "BS_DRY_RUN=1; export BS_DRY_RUN; bs_run touch '$CANARY'" >/dev/null
assert "bs_run under BS_DRY_RUN does not run the command" $([[ ! -e "$CANARY" ]] && echo 0 || echo 1)
bs "BS_DRY_RUN=1; export BS_DRY_RUN; bs_run_sh 'touch $CANARY'" >/dev/null
assert "bs_run_sh under BS_DRY_RUN does not run the command" $([[ ! -e "$CANARY" ]] && echo 0 || echo 1)
bs "bs_run touch '$CANARY'" >/dev/null
assert "bs_run without BS_DRY_RUN does run the command" $([[ -e "$CANARY" ]] && echo 0 || echo 1)

echo "== full bootstrap under dry run =="
out="$(bs 'BS_DRY_RUN=1; export BS_DRY_RUN; bs_bootstrap; echo "rc=$?"')"
assert "dry-run bootstrap succeeds" $(grep -q 'rc=0' <<<"$out" && echo 0 || echo 1)
# The invariant is "changes nothing", NOT "has nothing to change". On a host
# whose login shell is already zsh there is nothing pending; on a CI runner
# (login shell /bin/bash) a chsh is legitimately pending. Both are correct --
# what must never happen is an actual mutation.
login_now="$(bs 'bs_current_login_shell')"
case "$login_now" in
  */zsh)
    assert "  a fully provisioned host has nothing pending ($login_now)" \
      $(! grep -q 'DRY RUN' <<<"$out" && echo 0 || echo 1) ;;
  *)
    assert "  an unprovisioned host reports the login-shell change as pending ($login_now)" \
      $(grep -q 'DRY RUN' <<<"$out" && echo 0 || echo 1) ;;
esac
assert "  and the login shell is unchanged afterwards" \
  $([[ "$(bs 'bs_current_login_shell')" == "$login_now" ]] && echo 0 || echo 1)
assert "  and no chsh was actually executed" $(! grep -qE '^\s*\+ sudo chsh' <<<"$out" && echo 0 || echo 1)

echo "== the root guard is unconditional =="
# It used to be `if command -v refuse_if_root; then refuse_if_root; fi`, which
# silently skipped the check whenever fs-helpers.sh had not been sourced -- i.e.
# whenever REPO_ROOT was unset. A guard protecting an invariant must not depend
# on whether a helper happened to load.
out="$(/bin/sh -c "id() { echo 0; }; unset REPO_ROOT; . '$BS'; bs_bootstrap >/dev/null 2>&1; echo rc=\$?")"
assert "bs_bootstrap refuses root with REPO_ROOT unset" $(grep -q 'rc=1' <<<"$out" && echo 0 || echo 1)
out="$(/bin/sh -c "id() { echo 0; }; unset REPO_ROOT; . '$BS'; bs_exec_bash /dev/null >/dev/null 2>&1; echo rc=\$?")"
assert "bs_exec_bash refuses root with REPO_ROOT unset" $(grep -q 'rc=1' <<<"$out" && echo 0 || echo 1)
out="$(/bin/sh -c "id() { echo 0; }; unset REPO_ROOT; . '$BS'; bs_refuse_root 2>&1")"
assert "  and still explains itself without fs-helpers" \
  $(grep -qi 'refusing to run as root' <<<"$out" && echo 0 || echo 1)
# Control: a non-root run must get through, or the above passes trivially.
out="$(/bin/sh -c "unset REPO_ROOT; . '$BS'; bs_refuse_root; echo rc=\$?")"
assert "  (control) a non-root run is not refused" $(grep -q 'rc=0' <<<"$out" && echo 0 || echo 1)

BANNED="map""file"   # never spelled literally: this file scans itself
echo "== no suite uses \$BANNED ($BANNED) =="
# bash 4+. Under macOS's bash 3.2 it yields an EMPTY array and whatever loop
# depended on it is silently skipped -- which is how a behavioural guard shipped
# doing nothing. read_lines_into (lib/tests/assert.sh) is the replacement.
bad=""
for f in "$SCRIPT_DIR"/*.sh; do
  case "$(basename "$f")" in assert.sh) continue ;; esac
  # Comments AND single-quoted spans: the banned word appears in this very
  # check's own pattern string, which comment-stripping alone does not remove.
  sed -e 's/[[:space:]]*#.*$//' -e "s/'[^']*'/''/g" "$f" \
    | grep -q "$BANNED" && bad="$bad $(basename "$f")"
done
check "no test suite uses \$BANNED" "" "$bad"
# Control: the check must actually detect the thing it bans.
printf '%s -t X < <(echo a)\n' "$BANNED" > "$WORK/banned_probe.sh"
sed -e 's/[[:space:]]*#.*$//' -e "s/'[^']*'/''/g" "$WORK/banned_probe.sh" | grep -q "$BANNED"
assert "  (control) the ban detects a real usage" $?

echo "== brew shellenv persistence =="
# Two findings from the full-branch battle: the file was edited in place with no
# backup (and a dotfiles setup usually makes ~/.zprofile a symlink INTO the
# repo), and the idempotency check was a substring match.
ZP="$WORK/zphome"; mkdir -p "$ZP"
PFX="$(bs 'bs_brew_prefix')"
LINE="eval \"\$($PFX/bin/brew shellenv)\""

# A comment mentioning "brew shellenv" must NOT suppress the real append.
printf '# a comment mentioning brew shellenv\n' > "$ZP/.zprofile"
out="$(HOME="$ZP" bs 'bs_brew_persist')"
assert "a comment mentioning it does not suppress the append" \
  $(grep -q 'added brew shellenv' <<<"$out" && echo 0 || echo 1)
assert "  and the real line is now present" $(grep -qxF "$LINE" "$ZP/.zprofile" && echo 0 || echo 1)

# The exact line present -> skip.
out="$(HOME="$ZP" bs 'bs_brew_persist')"
assert "the exact line present is recognized and skipped" \
  $(grep -q 'already in' <<<"$out" && echo 0 || echo 1)
check "  and it is not appended twice" 1 "$(grep -cxF "$LINE" "$ZP/.zprofile")"

# A line for a DIFFERENT prefix must not count as ours. Derive "different" from
# the ACTUAL prefix: hardcoding /usr/local is only different on Apple Silicon,
# and on Linux it IS the prefix, so the line correctly read as already-present
# and this assertion failed for the right reason on the wrong premise.
OTHER_PFX="/opt/homebrew"
[ "$PFX" = "/opt/homebrew" ] && OTHER_PFX="/usr/local"
printf 'eval "$(%s/bin/brew shellenv)"\n' "$OTHER_PFX" > "$ZP/.zprofile"
out="$(HOME="$ZP" bs 'bs_brew_persist')"
assert "a different brew prefix does not count as already-present" \
  $(grep -q 'added brew shellenv' <<<"$out" && echo 0 || echo 1)

echo "== and a symlinked .zprofile is named and backed up, not silently rewritten =="
ZS="$WORK/zshome"; mkdir -p "$ZS/dotfiles"
printf 'export FOO=1\n' > "$ZS/dotfiles/.zprofile"
ln -s "$ZS/dotfiles/.zprofile" "$ZS/.zprofile"
out="$(HOME="$ZS" bs 'bs_brew_persist')"
assert "it says the target is a symlink and names the real file" \
  $(grep -q 'is a symlink; the line goes into' <<<"$out" && echo 0 || echo 1)
assert "  backs the real file up before appending" \
  $([[ -n "$(find "$ZS/dotfiles" -name '.zprofile.bak-*' 2>/dev/null)" ]] && echo 0 || echo 1)
assert "  the backup still holds the ORIGINAL content" \
  $(grep -q 'export FOO=1' "$(find "$ZS/dotfiles" -name '.zprofile.bak-*' | head -1)" && echo 0 || echo 1)
assert "  and the symlink itself is left intact (not replaced by a file)" \
  $([[ -L "$ZS/.zprofile" ]] && echo 0 || echo 1)

# A RELATIVE symlink, with fs-helpers deliberately out of scope so the readlink
# fallback runs. readlink returns the target verbatim, so appending to it wrote
# relative to the CURRENT DIRECTORY while reporting success.
ZR="$WORK/zrel"; mkdir -p "$ZR/dotfiles"
printf 'export BAR=1\n' > "$ZR/dotfiles/.zprofile"
( cd "$ZR" && ln -s "dotfiles/.zprofile" .zprofile )
CANARY="$WORK/canary-cwd"; mkdir -p "$CANARY/dotfiles"
out="$(cd "$CANARY" && HOME="$ZR" /bin/sh -c "unset REPO_ROOT; . '$BS'; bs_brew_persist" 2>&1)"
assert "a RELATIVE symlink resolves against the link's own directory" \
  $(grep -qF "$ZR/dotfiles/.zprofile" <<<"$out" && echo 0 || echo 1)
assert "  the line lands in the real dotfile" \
  $(grep -q 'brew shellenv' "$ZR/dotfiles/.zprofile" && echo 0 || echo 1)
assert "  and NOT relative to the current directory" \
  $([[ ! -e "$CANARY/dotfiles/.zprofile" ]] && echo 0 || echo 1)

# Quoting variations must not append a duplicate on every run.
ZV="$WORK/zvar"; mkdir -p "$ZV"
printf 'eval $(%s/bin/brew shellenv)\n' "$PFX" > "$ZV/.zprofile"
out="$(HOME="$ZV" bs 'bs_brew_persist')"
assert "an unquoted eval variant counts as already-present" \
  $(grep -q 'already in' <<<"$out" && echo 0 || echo 1)
check "  and nothing is appended" 1 "$(wc -l < "$ZV/.zprofile" | tr -d ' ')"
# Control: a COMMENT mentioning it must still not count.
printf '# eval "$(%s/bin/brew shellenv)"\n' "$PFX" > "$ZV/.zprofile"
out="$(HOME="$ZV" bs 'bs_brew_persist')"
assert "  (control) a comment still does not count as present" \
  $(grep -q 'added brew shellenv' <<<"$out" && echo 0 || echo 1)

echo "== login shell is readable without getent or dscl =="
# Neither is guaranteed: dscl is macOS-only, getent is absent on minimal images.
# Returning empty made bs_ensure_zsh_default unable to tell "already zsh" from
# "not zsh", so it proposed a chsh regardless.
# stdout ONLY: bs_current_login_shell prints the shell on stdout and warns on
# stderr, and production callers use "$(...)" which captures only stdout. The
# suite's bs() helper merges the two, which would fold the warning into the value.
lsh() { /bin/sh -c ". '$BS'; $1" 2>/dev/null; }
out="$(lsh 'bs_have() { [ "$1" != dscl ] && [ "$1" != getent ]; }; bs_current_login_shell')"
assert "falls back to /etc/passwd when dscl and getent are missing (got '$out')" \
  $([[ -n "$out" && "$out" == /* ]] && echo 0 || echo 1)
# Reaching the $SHELL fallback needs the /etc/passwd lookup to yield nothing
# too. Stubbing only bs_have is macOS-shaped: there the user is not in
# /etc/passwd (directory services hold the record) so the lookup naturally comes
# up empty, but on Linux the user IS there and the fallback is never reached.
# Stub awk as well so the branch is forced identically on both.
NOPASSWD='bs_have() { return 1; }; awk() { :; }; SHELL=/bin/zsh; export SHELL;'
out="$(lsh "$NOPASSWD bs_current_login_shell")"
assert "  and to \$SHELL when the passwd lookup yields nothing (got '$out')" \
  $([[ "$out" == "/bin/zsh" ]] && echo 0 || echo 1)
# The $SHELL fallback is a guess, so it must SAY so on stderr.
warn="$(/bin/sh -c ". '$BS'; $NOPASSWD bs_current_login_shell >/dev/null" 2>&1)"
assert "  and warns that \$SHELL may not be the login shell" \
  $(grep -qi 'may not be the login shell' <<<"$warn" && echo 0 || echo 1)
# Control: with the passwd lookup WORKING, the fallback must not fire, or the
# two assertions above would pass on any platform for the wrong reason.
warn2="$(/bin/sh -c ". '$BS'; bs_current_login_shell >/dev/null" 2>&1)"
assert "  (control) a working lookup does not warn" \
  $(! grep -qi 'may not be the login shell' <<<"$warn2" && echo 0 || echo 1)

echo "== brew is a hard prerequisite on macOS: no cascade =="
# It used to set _bs_rc=1 and carry on through zsh, bash and chsh, producing
# three more predictable failures after the one that mattered.
out="$(bs 'bs_ensure_brew() { return 1; }; BS_OS=mac; bs_bootstrap; echo rc=$?')"
if [[ "$(uname -s)" == "Darwin" ]]; then
  assert "a failed brew stops the bootstrap on macOS" $(grep -q 'rc=1' <<<"$out" && echo 0 || echo 1)
  assert "  saying why rather than cascading" $(grep -q 'stopping here' <<<"$out" && echo 0 || echo 1)
  assert "  and does not go on to try zsh/bash/chsh" \
    $(! grep -qE '^\[bootstrap\] (zsh|bash|login shell):' <<<"$out" && echo 0 || echo 1)
fi

echo "== login shell =="
out="$(bs 'bs_current_login_shell')"
assert "reads the current login shell (got '$out')" $([[ -n "$out" ]] && echo 0 || echo 1)
out="$(bs 'bs_preferred_login_zsh')"
assert "picks a preferred login zsh (got '$out')" $([[ -x "$out" ]] && echo 0 || echo 1)
# Behaviour depends on what the host's login shell actually is, and both
# branches are correct -- so assert the right one rather than assuming macOS.
out="$(bs 'BS_DRY_RUN=1; export BS_DRY_RUN; BS_ZSH_PREFER=system; export BS_ZSH_PREFER; bs_ensure_zsh_default')"
case "$(bs 'bs_current_login_shell')" in
  */zsh)
    # An already-zsh login shell must not be switched to chase a newer build.
    assert "leaves an existing zsh login shell alone" \
      $(grep -qE 'already (zsh|/)' <<<"$out" && echo 0 || echo 1) ;;
  *)
    assert "proposes zsh when the login shell is not zsh" \
      $(grep -q 'login shell:' <<<"$out" && echo 0 || echo 1) ;;
esac
assert "  and never executes chsh for real here" $(! grep -qE '^\s*\+ sudo chsh' <<<"$out" && echo 0 || echo 1)
out="$(bs 'BS_NO_CHSH=1; export BS_NO_CHSH; bs_ensure_zsh_default')"
assert "BS_NO_CHSH suppresses the login-shell change" $(grep -q 'leaving it alone' <<<"$out" && echo 0 || echo 1)
# /etc/shells already lists the target, so this must be a no-op, not a sudo call.
out="$(bs "bs_ensure_in_etc_shells '$(bs 'bs_preferred_login_zsh')'")"
assert "does not touch /etc/shells when the shell is already listed" $(! grep -q 'sudo' <<<"$out" && echo 0 || echo 1)

echo "== re-exec helpers =="
# bs_exec_zsh was deleted: nothing has needed it since machine-setup became a
# POSIX sh script, and dead code with a passing test looks maintained.
assert "bs_exec_zsh no longer exists" \
  $(! grep -qE '^bs_exec_zsh\(\)' "$BS" && echo 0 || echo 1)
assert "  and nothing outside bootstrap.sh references it" \
  $(! grep -rqE '\bbs_exec_zsh\b' "$SCRIPT_DIR/../../skills" 2>/dev/null && echo 0 || echo 1)

cat > "$WORK/probe.sh" <<'B'
echo "BASH_MAJOR=${BASH_VERSINFO[0]} argv=$*"
B
out="$(bs "bs_exec_bash '$WORK/probe.sh' three four")"
maj="$(sed -n 's/.*BASH_MAJOR=\([0-9]*\).*/\1/p' <<<"$out")"
assert "bs_exec_bash runs the script under bash >= 4 (major $maj)" $([[ "${maj:-0}" -ge 4 ]] && echo 0 || echo 1)
assert "  and forwards arguments" $(grep -q 'argv=three four' <<<"$out" && echo 0 || echo 1)
out="$(bs "bs_exec_bash '$WORK/nope.sh'")"
assert "re-exec of a missing script fails loudly" $(grep -q 'no such script' <<<"$out" && echo 0 || echo 1)

echo "== dry run reports no interpreter path rather than inventing one =="
# The dry-run branches used to set BS_ZSH=/usr/bin/zsh (wrong on macOS) and
# BS_BASH=$(bs_brew_prefix)/bin/bash (nonsense on Linux, and absent either way),
# then bs_exec_* would exec that phantom. Nothing was installed, so there is no
# path to report and the variable must stay empty.
STUB3="$WORK/bash3"
mkdir -p "$STUB3"
cat > "$STUB3/bash" <<'S3'
#!/bin/sh
case "$2" in
  *BASH_VERSINFO*) echo 3 ;;
  *BASH_VERSION*)  echo "3.2.57(1)-release" ;;
  *) exit 0 ;;
esac
S3
chmod +x "$STUB3/bash"
out="$(bs "BS_DRY_RUN=1; export BS_DRY_RUN
          BS_ASSUME_YES=1; export BS_ASSUME_YES
          BS_BASH_SEARCH='$STUB3/bash'; export BS_BASH_SEARCH
          PATH='$STUB3:/usr/bin:/bin'
          bs_detect_os; bs_detect_pkg_mgr
          bs_ensure_bash >/dev/null 2>&1
          echo \"BS_BASH=[\$BS_BASH]\"")"
assert "dry-run bs_ensure_bash leaves BS_BASH empty, not guessed" \
  $(grep -q 'BS_BASH=\[\]' <<<"$out" && echo 0 || echo 1)
assert "  and no /opt/homebrew guess leaks out" \
  $(! grep -q 'homebrew' <<<"$out" && echo 0 || echo 1)

# The guard itself. bs_exec_bash RE-RESOLVES BS_BASH on entry and will find or
# install a real bash, so presetting the variable proves nothing and on a
# developer machine the guard is unreachable. Stub the discovery instead, which
# is the only way to exercise the last-resort branch deterministically.
out="$(bs "bs_find_bash() { return 1; }
           bs_ensure_brew() { return 0; }
           bs_ensure_bash() { BS_BASH=''; return 0; }
           bs_exec_bash '$WORK/probe.sh' 2>&1; echo rc=\$?")"
assert "bs_exec_bash refuses when no interpreter was resolved" \
  $(grep -qE 'rc=[1-9]' <<<"$out" && echo 0 || echo 1)
assert "  saying no bash is available, not 'exec: not found'" \
  $(grep -qi 'no bash >=' <<<"$out" && echo 0 || echo 1)
assert "  and does not run the script" \
  $(! grep -q 'BASH_MAJOR=' <<<"$out" && echo 0 || echo 1)

# Same, with a path that is set but absent.
out="$(bs "bs_find_bash() { return 1; }
           bs_ensure_brew() { return 0; }
           bs_ensure_bash() { BS_BASH=/nonexistent/bash; return 0; }
           bs_exec_bash '$WORK/probe.sh' 2>&1; echo rc=\$?")"
assert "  and refuses a non-executable interpreter path" \
  $(grep -qE 'rc=[1-9]' <<<"$out" && echo 0 || echo 1)

# Under BS_DRY_RUN the refusal must explain that nothing was installed.
out="$(bs "BS_DRY_RUN=1; export BS_DRY_RUN
           bs_find_bash() { return 1; }
           bs_ensure_brew() { return 0; }
           bs_ensure_bash() { BS_BASH=''; return 0; }
           bs_exec_bash '$WORK/probe.sh' 2>&1")"
assert "  and a dry-run refusal says why nothing was installed" \
  $(grep -qi 'BS_DRY_RUN is set' <<<"$out" && echo 0 || echo 1)

# Control: with discovery working it must still actually exec.
out="$(bs "bs_exec_bash '$WORK/probe.sh' 2>&1")"
assert "  (control) it still execs when a real bash is available" \
  $(grep -q 'BASH_MAJOR=' <<<"$out" && echo 0 || echo 1)

echo ""
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
