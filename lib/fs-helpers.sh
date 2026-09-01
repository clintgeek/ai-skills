#!/bin/sh
# Shared filesystem helpers: backup-before-replace and mkdir-if-missing.
#
# POSIX sh on purpose. This logic used to exist twice -- once in bash
# (ai-setup.sh) and once in zsh (in the since-deleted lib/setup-helpers.zsh,
# which used the zsh-only `(( $+functions[log] ))`, so the bash side could not
# have converged on it even deliberately). THE_SPEC forbids that duplication.
# Keeping this POSIX is what lets one copy serve every caller.
#
# Source it; it runs nothing on its own:
#   . "$REPO_ROOT/lib/fs-helpers.sh"
#   bak="$(backup_path /some/path)"   # prints the .bak path, or empty
#   ensure_dir /some/dir
#
# One timestamp per process, so every path moved aside in a single run shares a
# suffix and repeated runs never collide.
: "${BACKUP_TIMESTAMP:=$(date +%Y%m%d-%H%M%S)}"

# Log through the caller's log() when it has one, so output keeps its prefix.
# Always to stderr: backup_path prints the backup location on stdout, and a log
# line mixed into that would corrupt `bak="$(backup_path ...)"`.
# NOTE: `command -v log` is wrong here -- macOS ships /usr/bin/log, so on a Mac
# it matches the system logging binary whenever the caller has no log()
# function, and every message goes to `log` as a bogus subcommand. Match on
# "function" instead, which `type` reports in bash, zsh and dash alike.
_fs_log() {
  case "$(type log 2>/dev/null)" in
    *function*) log "$@" >&2 ;;
    *)          echo "$@" >&2 ;;
  esac
}

# Absolute, normalized target of the symlink $1.
#
# `readlink` returns the target VERBATIM, which may be relative -- a link made
# by hand as `ln -s ../../.ai/skills` reads back as "../../.ai/skills". Comparing
# that against an absolute root never matches, so a link that IS ours was
# treated as a stranger's and backed up on every single re-run.
#
# No `readlink -f`: that is a GNU extension and macOS does not have it. No
# `realpath` either, for the same reason. Resolved with `cd` in a subshell, which
# is POSIX and also normalizes away `..` and `.`.
#
# Only called on a link that resolves -- backup_path removes dangling links
# before this point -- so the cd is safe.
_fs_abs_link_target() {
  _fs_t="$(readlink "$1" 2>/dev/null)" || return 1
  [ -n "$_fs_t" ] || return 1
  case "$_fs_t" in
    /*) ;;                                    # already absolute
    *)  _fs_t="$(dirname "$1")/$_fs_t" ;;     # relative to the LINK's directory
  esac
  if [ -d "$_fs_t" ]; then
    (cd "$_fs_t" 2>/dev/null && pwd) || return 1
  else
    # A file: normalize the directory and keep the basename.
    _fs_dir="$(dirname "$_fs_t")"
    _fs_base="$(basename "$_fs_t")"
    _fs_dir="$(cd "$_fs_dir" 2>/dev/null && pwd)" || return 1
    echo "$_fs_dir/$_fs_base"
  fi
}

# Is this a symlink pointing inside the given root? Those are ours, from an
# earlier run, and carry no data worth preserving.
_fs_link_points_into() {
  _fs_target="$(_fs_abs_link_target "$1")" || return 1
  # Normalize the root as well, so a symlinked home (/Users/x -> /home/x) or a
  # trailing slash cannot make an identical path compare unequal.
  _fs_root="$(cd "$2" 2>/dev/null && pwd)" || _fs_root="${2%/}"
  case "$_fs_target" in
    # Exact match, or a path BELOW the root. Not a string prefix: that would
    # make /Users/x/.ai-backup look like it lives under /Users/x/.ai.
    "$_fs_root"|"$_fs_root"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Move an existing path aside and print where it went. Prints nothing if there
# was nothing there.
#
# Two cases are removed rather than backed up, because a symlink holds no
# content and a stale copy of one is pure clutter:
#   - a dangling symlink (its target is already gone)
#   - a symlink already pointing inside $AI_ROOT (one of ours, being re-pointed)
# Everything else -- real files, real directories, symlinks to somewhere we do
# not own -- is always moved, never deleted.
backup_path() {
  path="$1"
  if [ -L "$path" ]; then
    if [ ! -e "$path" ]; then
      _fs_log "  removing dangling symlink $path -> $(readlink "$path" 2>/dev/null)"
      rm -f "$path"
      echo ""
      return 0
    fi
    if [ -n "${AI_ROOT:-}" ] && _fs_link_points_into "$path" "$AI_ROOT"; then
      _fs_log "  replacing our own symlink $path -> $(readlink "$path" 2>/dev/null)"
      rm -f "$path"
      echo ""
      return 0
    fi
  fi
  if [ -e "$path" ] || [ -L "$path" ]; then
    bak="${path}.bak-${BACKUP_TIMESTAMP}"
    _fs_log "  backing up $path -> $bak"
    mv "$path" "$bak" || return 1
    echo "$bak"
    return 0
  fi
  echo ""
  return 0
}

ensure_dir() {
  if [ ! -d "$1" ]; then
    mkdir -p "$1" || return 1
    _fs_log "  created $1"
  fi
  return 0
}
