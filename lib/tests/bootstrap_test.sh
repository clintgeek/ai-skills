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
out="$(bs 'echo "BS_SUDO=$BS_SUDO"' < /dev/null)"
assert "with no terminal, escalation uses sudo -n (fail fast)" \
  $(grep -q 'BS_SUDO=sudo -n' <<<"$out" && echo 0 || echo 1)
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
