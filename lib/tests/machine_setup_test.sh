#!/usr/bin/env bash
# Tests for skills/machine-setup/scripts/machine-setup, the bootstrap entry point.
#
# The app catalog, role taxonomy and checklist this used to test are gone --
# deliberately. Those encoded knowledge a model can just look up, and every
# self-inflicted bug in this subsystem lived in them. What remains is the part
# that must be a guarantee rather than a recollection: POSIX purity, consent
# gating, and refusing to touch a directory that is not ours.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MS="$REPO_ROOT/skills/machine-setup/scripts/machine-setup"

PASS=0 FAIL=0
check() { if [[ "$2" == "$3" ]]; then PASS=$((PASS+1)); echo "  ok: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1 (expected '$2', got '$3')" >&2; fi }
assert() { if [[ "$2" -eq 0 ]]; then PASS=$((PASS+1)); echo "  ok: $1"; else FAIL=$((FAIL+1)); echo "  FAIL: $1" >&2; fi }

# Print the CODE of a shell file: comments and single-quoted spans removed.
# Searching a file for a construct it documents avoiding otherwise matches the
# documentation -- which happened repeatedly in this session before this existed.
code_of() { sed -e 's/[[:space:]]*#.*$//' -e "s/'[^']*'/''/g" "$1"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/machine_setup_test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM

echo "== POSIX purity =="
# This runs before zsh and before bash 4 exist. It cannot use them.
/bin/sh -n "$MS" >/dev/null 2>&1; assert "parses as POSIX sh" $?
if command -v dash >/dev/null 2>&1; then
  dash -n "$MS" >/dev/null 2>&1; assert "parses under dash (strict POSIX)" $?
fi
head -1 "$MS" | grep -qx -- '#!/bin/sh'; assert "declares #!/bin/sh" $?
CODE="$WORK/ms.code.sh"
# Strip comments AND single-quoted spans. A regex like '^REPO_PATH\[[a-z]+\]'
# handed to grep contains "[[" but is not a bash conditional, and matching it
# is a false alarm rather than a finding.
sed -e "s/[[:space:]]*#.*$//" -e "s/'[^']*'/''/g" "$MS" > "$CODE"
! grep -nE '\[\[|declare -|typeset -|\$\{[A-Za-z_]+\[|<<<|\blocal\b' "$CODE" >/dev/null
assert "contains no bash/zsh-only constructs" $?
# Prove the check can still fail, so it cannot rot into a no-op.
printf 'if [[ x = x ]]; then :; fi\n' > "$WORK/bashism_probe.sh"
grep -qE '\[\[' "$WORK/bashism_probe.sh"
assert "  (control) the bashism check does detect [[ ]]" $?

echo "== it does not install apps =="
# The whole point of the rewrite. If a catalog comes back, this fails.
! grep -qE 'brew install (git|jq|firefox|--cask)' "$MS"; assert "no app install commands in the script" $?
[[ ! -f "$REPO_ROOT/lib/app-catalog.zsh" ]]; assert "no app catalog in the repo" $?

echo "== dry run mutates nothing =="
# Capture real state, not "is anything pending". A host whose login shell is
# already zsh has nothing pending; a fresh box or CI runner legitimately has a
# chsh pending. The guarantee is that NEITHER changes anything.
if [[ "$(uname -s)" == "Darwin" ]]; then
  shell_before="$(dscl . -read "/Users/$(id -un)" UserShell 2>/dev/null | awk '{print $2}')"
else
  shell_before="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)"
fi
shells_before="$(cksum /etc/shells 2>/dev/null | awk '{print $1}')"
zprofile_before="$(cksum "$HOME/.zprofile" 2>/dev/null | awk '{print $1}' || echo none)"

out="$("$MS" --dry-run --no-clis < /dev/null 2>&1)"
assert "dry run succeeds" $?
assert "  reaches the end" $(grep -q 'done\.' <<<"$out" && echo 0 || echo 1)

if [[ "$(uname -s)" == "Darwin" ]]; then
  shell_after="$(dscl . -read "/Users/$(id -un)" UserShell 2>/dev/null | awk '{print $2}')"
else
  shell_after="$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)"
fi
shells_after="$(cksum /etc/shells 2>/dev/null | awk '{print $1}')"
zprofile_after="$(cksum "$HOME/.zprofile" 2>/dev/null | awk '{print $1}' || echo none)"

check "  login shell unchanged" "$shell_before" "$shell_after"
check "  /etc/shells unchanged" "$shells_before" "$shells_after"
check "  ~/.zprofile unchanged" "$zprofile_before" "$zprofile_after"
assert "  and no command was executed" $(! grep -qE '^\s*\+ ' <<<"$out" && echo 0 || echo 1)
out="$("$MS" --dry-run < /dev/null 2>&1)"
assert "dry run does not run ai-setup for real" $(grep -q 'DRY RUN: would run: ai-setup select' <<<"$out" && echo 0 || echo 1)

echo "== consent =="
out="$("$MS" --dry-run --clis all < /dev/null 2>&1)"
assert "--clis is passed through to ai-setup" $(grep -q 'ai-setup select --clis all' <<<"$out" && echo 0 || echo 1)
assert "  and --yes is not invented when absent" $(! grep -q 'select --clis all --yes' <<<"$out" && echo 0 || echo 1)
out="$("$MS" --dry-run --clis all --yes < /dev/null 2>&1)"
assert "--yes is passed through when given" $(grep -q 'select --clis all --yes' <<<"$out" && echo 0 || echo 1)

echo "== repo step refuses to touch what is not ours =="
# A non-git directory at a configured path must be left alone, not backed up and
# cloned over. Losing someone's ~/dotfiles is not a bootstrapper's call.
assert "refuses a non-checkout path rather than moving it" \
  $(grep -q 'is not a git checkout -- leaving it alone' "$MS" && echo 0 || echo 1)
assert "  and says who decides" $(grep -q 'Move it aside yourself' "$MS" && echo 0 || echo 1)
! grep -q 'backup_path' "$MS"; assert "  and never backs up a repo path on its own" $?

echo "== flags =="
"$MS" --help < /dev/null >/dev/null 2>&1; check "--help exits 0" 0 $?
"$MS" --nonsense < /dev/null >/dev/null 2>&1; check "an unknown flag exits 1" 1 $?
out="$("$MS" --dry-run --no-repos --no-clis < /dev/null 2>&1)"
assert "--no-repos skips the repo step" $(grep -q 'repos (skipped)' <<<"$out" && echo 0 || echo 1)
assert "--no-clis skips the CLI step" $(grep -qE 'AI CLIs$' <<<"$out" && echo 0 || echo 1)

echo "== ai-setup reports usage errors before environment errors =="
# An unknown tool name is a usage error whether or not the repo is checked out
# at ~/.ai. On a CI runner it is not (the checkout is at the workspace path), and
# require_repo used to fire first -- telling someone who mistyped a name to go
# clone a repo.
AS="$REPO_ROOT/skills/ai-setup/scripts/ai-setup.sh"
for root in "$REPO_ROOT" /definitely/not/here; do
  out="$(AI_ROOT="$root" "$AS" hotwire definitely-not-a-tool 2>&1 || true)"
  assert "unknown tool is a usage error with AI_ROOT=$(basename "$root")" \
    $(grep -q 'no built-in path map' <<<"$out" && echo 0 || echo 1)
  assert "  and never an unbound-variable crash" \
    $(! grep -q 'unbound variable' <<<"$out" && echo 0 || echo 1)
done
# But a REAL tool with a missing repo must still refuse, or P1-6 is back.
if command -v claude >/dev/null 2>&1; then
  out="$(AI_ROOT=/definitely/not/here "$AS" hotwire claude 2>&1 || true)"
  assert "a real tool with a missing repo still refuses to link" \
    $(grep -q 'Refusing to link tools at a missing repo' <<<"$out" && echo 0 || echo 1)
  assert "  and creates nothing" $([[ ! -d /definitely ]] && echo 0 || echo 1)
fi

echo "== repos.conf paths expand without eval =="
# The parser used `eval "echo \"$rpath\""` to expand a literal $HOME, which
# executes command substitution embedded in a path value. repos.conf is committed
# data the owner controls, but reading data should not require an eval.
! code_of "$MS" | grep -qE 'eval "echo'
assert "no eval-based path expansion remains" $?

out="$("$MS" --dry-run --no-clis < /dev/null 2>&1)"
assert "\$HOME in repos.conf still resolves to a real path" \
  $(grep -qF "$HOME" <<<"$out" && echo 0 || echo 1)

# The point of dropping eval: a command substitution in a path value must be
# treated as literal text, never executed.
EVILDIR="$WORK/evilrepo"; mkdir -p "$EVILDIR"
cp -R "$REPO_ROOT/lib" "$REPO_ROOT/skills" "$EVILDIR/" 2>/dev/null
cat > "$EVILDIR/skills/machine-setup/repos.conf" <<EOF
MACHINE_REPOS=(evil)
typeset -A REPO_NAME REPO_PATH REPO_URL REPO_POST_CLONE
REPO_NAME[evil]="Evil"
REPO_PATH[evil]="\$HOME/probe-\$(touch $WORK/PWNED && echo pwned)"
REPO_URL[evil]="https://example.invalid/x.git"
REPO_POST_CLONE[evil]=""
EOF
rm -f "$WORK/PWNED"
"$EVILDIR/skills/machine-setup/scripts/machine-setup" --dry-run --no-clis < /dev/null >/dev/null 2>&1
assert "a command substitution in a repo path is NOT executed" \
  $([[ ! -e "$WORK/PWNED" ]] && echo 0 || echo 1)
# The post-clone hook IS still eval'd, deliberately: it is a hook, and running it
# is the point. It must be logged before it runs so it is never a surprise.
assert "the post-clone hook is logged before it runs" \
  $(grep -q 'log "    post-clone: \$rpost"' "$MS" && echo 0 || echo 1)

echo "== the CLI roster is shared, not duplicated =="
# Line-anchored: a mention in a comment is not a definition.
cd "$REPO_ROOT"
for fn in tool_roster resolve_tool_selection tool_install_one; do
  n=$(grep -rlE "^${fn}\(\)" $(git ls-files '*.sh' '*.zsh') 2>/dev/null | wc -l | tr -d ' ')
  check "$fn is defined exactly once" 1 "$n"
done
out="$(bash -c "source '$REPO_ROOT/skills/ai-setup/lib/ai-tools.sh'; resolve_tool_selection '2, claude 11 bogus' 2>/dev/null | tr '\n' ' '")"
check "selection resolves numbers, names and dedupes" "claude qwen " "$out"
for sh in bash zsh; do
  if command -v "$sh" >/dev/null 2>&1; then
    o="$($sh -c "source '$REPO_ROOT/skills/ai-setup/lib/ai-tools.sh'; resolve_tool_selection '2' | tr -d '\n'")"
    check "  same answer under $sh (arrays index differently)" "claude" "$o"
  fi
done

echo ""
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
