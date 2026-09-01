#!/usr/bin/env bash
# Tests for lib/fs-helpers.sh — backup-before-replace, shared by ai-setup and
# machine-setup.
#
# This file had no suite until now, which is how the relative-symlink bug below
# survived: backup_path's branches were verified by hand once and never again.
# The invariant that matters most is the destructive one — real files and
# directories are MOVED, never deleted.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FS="$SCRIPT_DIR/../fs-helpers.sh"

PASS=0 FAIL=0
check() { if [[ "$2" == "$3" ]]; then PASS=$((PASS+1)); echo "  ok: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')" >&2; fi }
assert() { if [[ "$2" -eq 0 ]]; then PASS=$((PASS+1)); echo "  ok: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1" >&2; fi }

W="$(mktemp -d "${TMPDIR:-/tmp}/fs_helpers_test.XXXXXX")"
trap 'rm -rf "$W"' EXIT INT TERM
# Resolve, so comparisons are not defeated by /var -> /private/var on macOS.
W="$(cd "$W" && pwd -P)"

# Run a snippet in POSIX sh with fs-helpers sourced and AI_ROOT set.
fs() { /bin/sh -c "AI_ROOT='$W/root'; export AI_ROOT; . '$FS'; $1" 2>&1; }

echo "== POSIX purity =="
/bin/sh -n "$FS" >/dev/null 2>&1; assert "parses as POSIX sh" $?
if command -v dash >/dev/null 2>&1; then dash -n "$FS" >/dev/null 2>&1; assert "parses under dash" $?; fi
# No readlink -f / realpath: both are GNU extensions absent on macOS. Strip
# comments first -- the file documents that it avoids them, and matching the
# explanation instead of the code is a false alarm.
! sed -e "s/[[:space:]]*#.*$//" "$FS" | grep -qE 'readlink +-f|\brealpath\b'
assert "uses no readlink -f or realpath (absent on macOS)" $?

mkdir -p "$W/root/skills/nested" "$W/home" "$W/elsewhere" "$W/root-backup"
echo content > "$W/root/afile"

echo "== link classification: relative targets count as ours =="
# readlink returns the target verbatim, so a hand-made `ln -s ../../.ai/skills`
# reads back relative and never matched an absolute root. Every re-run then
# backed up a link that was ours, piling up .bak-<timestamp> symlinks.
ln -s "../root/skills"        "$W/home/rel"
ln -s "$W/root/skills"        "$W/home/abs"
ln -s "../root"               "$W/home/relroot"
ln -s "../root/afile"         "$W/home/relfile"
ln -s "../root/skills/nested" "$W/home/reldeep"
for l in rel abs relroot relfile reldeep; do
  # rc MUST be captured before any other command substitution runs.
  fs "_fs_link_points_into '$W/home/$l' \"\$AI_ROOT\"" >/dev/null; rc=$?
  tgt="$(readlink "$W/home/$l" | sed "s|$W|\$W|")"
  assert "'$l' ($tgt) is recognized as ours" "$rc"
done

echo "== and a stranger's link is never claimed =="
ln -s "$W/elsewhere"         "$W/home/foreign"
ln -s "$W/root-backup"       "$W/home/prefixtrap"
ln -s "../root/../elsewhere" "$W/home/sneaky"
for l in foreign prefixtrap sneaky; do
  fs "_fs_link_points_into '$W/home/$l' \"\$AI_ROOT\"" >/dev/null; rc=$?
  tgt="$(readlink "$W/home/$l" | sed "s|$W|\$W|")"
  assert "'$l' ($tgt) is NOT claimed as ours" $([[ "$rc" -ne 0 ]] && echo 0 || echo 1)
done

# Control: the classifier must be capable of BOTH answers, or the two loops
# above could both be passing on a stuck return value.
fs "_fs_link_points_into '$W/home/rel' \"\$AI_ROOT\"" >/dev/null; ours_rc=$?
fs "_fs_link_points_into '$W/home/foreign' \"\$AI_ROOT\"" >/dev/null; foreign_rc=$?
assert "(control) the classifier returns different answers for ours vs foreign" \
  $([[ "$ours_rc" -eq 0 && "$foreign_rc" -ne 0 ]] && echo 0 || echo 1)
# prefixtrap is the one that would break under a naive string prefix.
assert "  (prefixtrap proves it is not a string-prefix match)" \
  $([[ -d "$W/root-backup" ]] && echo 0 || echo 1)

echo "== backup_path: our own links are REPLACED, not accumulated =="
ln -s "../root/skills" "$W/home/ourlink"
out="$(fs "backup_path '$W/home/ourlink'")"
assert "a relative link of ours is removed, not backed up" $([[ ! -L "$W/home/ourlink" ]] && echo 0 || echo 1)
check "  and returns no backup path" "" "$(fs "backup_path '$W/home/gone-now'" | tail -1)"
assert "  leaving no .bak clutter" $([[ -z "$(find "$W/home" -maxdepth 1 -name 'ourlink.bak-*' 2>/dev/null)" ]] && echo 0 || echo 1)

echo "== backup_path: a dangling link is removed =="
ln -s "$W/nothing-here" "$W/home/dangle"
fs "backup_path '$W/home/dangle'" >/dev/null
assert "dangling link removed" $([[ ! -L "$W/home/dangle" ]] && echo 0 || echo 1)
assert "  and not backed up" $([[ -z "$(find "$W/home" -maxdepth 1 -name 'dangle.bak-*' 2>/dev/null)" ]] && echo 0 || echo 1)

echo "== backup_path NEVER destroys data =="
# The load-bearing invariant. A real file, a real directory, and a link to
# somewhere we do not own are always moved aside with their content intact.
mkdir -p "$W/home/realdir"; echo precious > "$W/home/realdir/data.txt"
bak="$(fs "backup_path '$W/home/realdir'" | tail -1)"
assert "a real directory is moved, not deleted" $([[ -d "$bak" ]] && echo 0 || echo 1)
check "  with its content intact" "precious" "$(cat "$bak/data.txt" 2>/dev/null)"
assert "  and the original path is free" $([[ ! -e "$W/home/realdir" ]] && echo 0 || echo 1)

echo irreplaceable > "$W/home/realfile"
bak="$(fs "backup_path '$W/home/realfile'" | tail -1)"
check "a real file is moved, not deleted" "irreplaceable" "$(cat "$bak" 2>/dev/null)"

ln -s "$W/elsewhere" "$W/home/theirs"
bak="$(fs "backup_path '$W/home/theirs'" | tail -1)"
assert "a stranger's link is moved, not deleted" $([[ -L "$bak" ]] && echo 0 || echo 1)
assert "  and still points where it did" $([[ "$(readlink "$bak")" == "$W/elsewhere" ]] && echo 0 || echo 1)

echo "== backup_path on nothing is a no-op =="
out="$(fs "backup_path '$W/home/absent'; echo rc=\$?")"
assert "returns success" $(grep -q 'rc=0' <<<"$out" && echo 0 || echo 1)
assert "  and creates nothing" $([[ ! -e "$W/home/absent" ]] && echo 0 || echo 1)

echo "== ensure_dir =="
fs "ensure_dir '$W/home/a/b/c'" >/dev/null
assert "creates nested directories" $([[ -d "$W/home/a/b/c" ]] && echo 0 || echo 1)
out="$(fs "ensure_dir '$W/home/a/b/c'; echo rc=\$?")"
assert "  is idempotent and silent on an existing dir" \
  $(grep -q 'rc=0' <<<"$out" && ! grep -q 'created' <<<"$out" && echo 0 || echo 1)

echo "== refuse_if_sudo: never configure the wrong user's account =="
# The username varies per machine (ccrocker / crocker / rallycenter), so
# everything derives from $HOME and `id -un`. Under sudo BOTH become root's, so
# the repo, the symlinks, the login shell and .zprofile all land on root --
# silently, and reporting success. `sudo ./machine-setup` is a natural thing to
# type because it does install packages.
out="$(/bin/sh -c ". '$FS'; refuse_if_sudo; echo rc=\$?" 2>&1)"
assert "a normal run is unaffected" $(grep -q 'rc=0' <<<"$out" && echo 0 || echo 1)

out="$(/bin/sh -c "SUDO_USER=rallycenter; export SUDO_USER; . '$FS'; refuse_if_sudo; echo rc=\$?" 2>&1)"
assert "sudo from a real user is refused" $(grep -q 'rc=1' <<<"$out" && echo 0 || echo 1)
assert "  and the message names that user, not a generic warning" \
  $(grep -q 'rallycenter' <<<"$out" && echo 0 || echo 1)
assert "  and says how to run it correctly" $(grep -q 'sudo -u rallycenter' <<<"$out" && echo 0 || echo 1)

# Being root is not itself wrong: on many VPSes root is simply who you are.
out="$(/bin/sh -c "unset SUDO_USER; . '$FS'; refuse_if_sudo; echo rc=\$?" 2>&1)"
assert "genuinely being root (no SUDO_USER) is allowed" $(grep -q 'rc=0' <<<"$out" && echo 0 || echo 1)
out="$(/bin/sh -c "SUDO_USER=root; export SUDO_USER; . '$FS'; refuse_if_sudo; echo rc=\$?" 2>&1)"
assert "  as is SUDO_USER=root" $(grep -q 'rc=0' <<<"$out" && echo 0 || echo 1)
out="$(/bin/sh -c "SUDO_USER=rallycenter FS_ALLOW_SUDO=1; export SUDO_USER FS_ALLOW_SUDO; . '$FS'; refuse_if_sudo; echo rc=\$?" 2>&1)"
assert "  and FS_ALLOW_SUDO=1 overrides deliberately" $(grep -q 'rc=0' <<<"$out" && echo 0 || echo 1)

echo "== the entry points actually enforce it =="
MS="$SCRIPT_DIR/../../skills/machine-setup/scripts/machine-setup"
AS="$SCRIPT_DIR/../../skills/ai-setup/scripts/ai-setup.sh"
SUDO_USER=rallycenter HOME="$W/fakeroot" "$MS" --dry-run --no-clis < /dev/null >/dev/null 2>&1; rc=$?
check "machine-setup exits non-zero under sudo" 1 "$rc"
SUDO_USER=rallycenter HOME="$W/fakeroot" "$AS" inventory >/dev/null 2>&1; rc=$?
check "ai-setup exits non-zero under sudo" 1 "$rc"
assert "  and neither created anything in the fake root home" \
  $([[ ! -e "$W/fakeroot" ]] && echo 0 || echo 1)

echo "== logging goes to stderr, never into the returned path =="
# backup_path prints the backup location on stdout; a log line mixed in would
# corrupt bak="$(backup_path ...)".
echo x > "$W/home/logprobe"
out="$(/bin/sh -c "AI_ROOT='$W/root'; export AI_ROOT; . '$FS'; backup_path '$W/home/logprobe' 2>/dev/null")"
assert "stdout is exactly the backup path" $([[ "$out" == "$W/home/logprobe.bak-"* ]] && echo 0 || echo 1)
# And it must not shell out to macOS's /usr/bin/log when the caller has no log().
out="$(/bin/sh -c ". '$FS'; ln -s /nowhere '$W/home/logprobe2'; backup_path '$W/home/logprobe2'" 2>&1)"
assert "no caller log() means plain echo, not /usr/bin/log" \
  $(! grep -qi 'Unknown subcommand' <<<"$out" && echo 0 || echo 1)

echo ""
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
