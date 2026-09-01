#!/bin/sh
# Shared machine bootstrapper: guarantees the shells and package manager that
# every other script in this repo assumes.
#
# THIS FILE MUST STAY POSIX sh. It runs BEFORE zsh or a modern bash is known to
# exist -- that is the whole point of it -- so no [[ ]], no arrays, no
# associative arrays, and nothing else that needs the shells it installs.
# `sh -n lib/bootstrap.sh` is enforced in CI.
#
# Usage (source it; it runs nothing on its own):
#   . "$REPO_ROOT/lib/bootstrap.sh"
#   bs_bootstrap                 # brew (mac) + zsh + modern bash + zsh default
#   bs_exec_bash <script> "$@"   # re-exec a .sh script under bash 4+
#
# There is deliberately no bs_exec_zsh: nothing needs it since machine-setup
# became a POSIX sh script. If a zsh consumer appears, it comes back with that
# consumer rather than sitting here as dead code with a passing test.
#
# Knobs (environment):
#   BS_ASSUME_YES=1   install without prompting (the caller's --yes)
#   BS_DRY_RUN=1      print every mutation, change nothing
#   BS_NO_CHSH=1      install zsh but never touch the login shell
#   BS_ZSH_PREFER     'system' (default) or 'newest' -- which zsh becomes the
#                     login shell. 'system' keeps /bin/zsh on macOS, which
#                     survives a broken or unmounted Homebrew; 'newest' picks
#                     the highest version found.
#
# Testing knobs (override the absolute-path candidate lists so the "nothing
# installed yet" paths can be exercised on a machine that has everything):
#   BS_BASH_SEARCH        candidate bash paths        (default: brew, /usr/local, /usr/bin, /bin)
#   BS_ZSH_SEARCH         candidate zsh paths         (default: /bin, /usr/bin, /usr/local, brew)
#   BS_SYSTEM_ZSH_SEARCH  "system" zsh paths for the login-shell preference

BS_MIN_BASH_MAJOR=4
BS_BASH=""          # set by bs_ensure_bash: path to a bash >= BS_MIN_BASH_MAJOR
BS_ZSH=""           # set by bs_ensure_zsh: path to a usable zsh
BS_PKG_MGR=""       # set by bs_detect_pkg_mgr
BS_OS=""            # mac | linux | windows

bs_log()  { echo "[bootstrap] $*"; }
bs_warn() { echo "[bootstrap] $*" >&2; }
bs_die()  { echo "[bootstrap] error: $*" >&2; return 1; }

bs_have() { command -v "$1" >/dev/null 2>&1; }

# How to escalate.
#
#   already root  -> EMPTY. No escalation is needed, and a freshly provisioned
#                    VPS often drops you in as root on an image with no `sudo`
#                    installed at all, where prefixing it fails for no reason.
#   no terminal   -> `sudo -n`. cron, cloud-init and provisioning scripts cannot
#                    answer a password prompt, so fail fast rather than block on
#                    stdin forever.
#   otherwise     -> plain `sudo`, which may prompt, which is fine.
#
# Unquoted at the call sites on purpose: empty must expand to nothing.
BS_SUDO="sudo"
if [ "$(id -u)" = "0" ]; then
  BS_SUDO=""
elif [ ! -t 0 ]; then
  BS_SUDO="sudo -n"
fi

# Can we escalate right now without a password? Passwordless sudo (the usual VPS
# setup) says yes; a Mac asking for a password says no.
bs_sudo_passwordless() {
  bs_have sudo || return 1
  sudo -n true 2>/dev/null
}

# Warn BEFORE any work when root will likely be needed and cannot be had. This
# used to fail late: plan shown, confirmed, packages half installed, and then
# `sudo chsh` hit a prompt nobody could answer.
bs_check_sudo() {
  if [ "$(id -u)" = "0" ]; then
    return 0                      # already root; nothing to escalate
  fi
  if bs_sudo_passwordless; then
    return 0
  fi
  if [ -t 0 ]; then
    bs_log "sudo will ask for your password if a step needs root."
    return 0
  fi
  bs_warn "sudo needs a password and there is no terminal to type it into."
  bs_warn "  Steps needing root will fail: package installs, chsh, /etc/shells."
  bs_warn "  Run interactively, or configure passwordless sudo, or skip those steps."
  return 1
}

# Run a mutating command, honoring BS_DRY_RUN.
bs_run() {
  if [ -n "${BS_DRY_RUN:-}" ]; then
    bs_log "  DRY RUN: $*"
    return 0
  fi
  bs_log "  + $*"
  "$@"
}

# Same, for a command that must go through a shell (pipes, command substitution).
bs_run_sh() {
  if [ -n "${BS_DRY_RUN:-}" ]; then
    bs_log "  DRY RUN: $1"
    return 0
  fi
  bs_log "  + $1"
  /bin/sh -c "$1"
}

bs_confirm() {
  [ -n "${BS_ASSUME_YES:-}" ] && return 0
  [ -n "${BS_DRY_RUN:-}" ] && return 0
  if [ ! -t 0 ]; then
    bs_warn "  non-interactive and no --yes: skipping '$1'"
    return 1
  fi
  printf '%s [y/N] ' "$1"
  read -r _bs_answer
  case "$_bs_answer" in
    [Yy]*) return 0 ;;
    *) bs_log "  skipped."; return 1 ;;
  esac
}

bs_detect_os() {
  case "$(uname -s)" in
    Darwin) BS_OS="mac" ;;
    Linux) BS_OS="linux" ;;
    MINGW*|MSYS*|CYGWIN*) BS_OS="windows" ;;
    *) BS_OS="linux" ;;
  esac
}

# macOS has no system package manager, so brew IS the package manager there.
bs_detect_pkg_mgr() {
  [ -z "$BS_OS" ] && bs_detect_os
  BS_PKG_MGR=""
  if [ "$BS_OS" = "mac" ]; then
    bs_have brew && BS_PKG_MGR="brew"
    return 0
  fi
  for _bs_mgr in apt-get apt dnf yum pacman zypper apk; do
    if bs_have "$_bs_mgr"; then
      BS_PKG_MGR="$_bs_mgr"
      return 0
    fi
  done
  return 0
}

# Install one package with whatever manager this machine has.
bs_pkg_install() {
  _bs_pkg="$1"
  [ -z "$BS_PKG_MGR" ] && bs_detect_pkg_mgr
  case "$BS_PKG_MGR" in
    brew)         bs_run brew install "$_bs_pkg" ;;
    apt-get|apt)  bs_run_sh "$BS_SUDO $BS_PKG_MGR update -qq && $BS_SUDO $BS_PKG_MGR install -y $_bs_pkg" ;;
    dnf|yum)      bs_run $BS_SUDO "$BS_PKG_MGR" install -y "$_bs_pkg" ;;
    pacman)       bs_run $BS_SUDO pacman -S --noconfirm "$_bs_pkg" ;;
    zypper)       bs_run $BS_SUDO zypper install -y "$_bs_pkg" ;;
    apk)          bs_run $BS_SUDO apk add --no-cache "$_bs_pkg" ;;
    *)            bs_die "no supported package manager found; install $_bs_pkg manually" ;;
  esac
}

# ---------------------------------------------------------------------------
# Homebrew (macOS)
# ---------------------------------------------------------------------------
# Apple ships no package manager, so on macOS brew is a hard prerequisite for
# everything downstream -- installing zsh, installing a modern bash, and any app
# an agent later decides to install. Without it a fresh Mac can do none of that.

# This is `curl | bash`, deliberately and with the owner's sign-off (2026-09-01).
# It is Homebrew's only sanctioned install path -- there is no signed package --
# and it is exactly what a human would paste into the same terminal, with the
# same assumptions. Pinning a commit instead of HEAD would mean running an
# installer upstream no longer tests. The same trust model already applies to
# every AI CLI in the registry and to oh-my-zsh, so singling brew out would be
# inconsistent rather than safer. Raised by an ai-battle challenger and declined
# on the merits; do not "harden" this into a checksum prompt nobody reads.
BS_BREW_INSTALLER='/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'

# Homebrew lives at /opt/homebrew on Apple Silicon and /usr/local on Intel.
bs_brew_prefix() {
  if [ -x /opt/homebrew/bin/brew ]; then
    echo /opt/homebrew
  elif [ -x /usr/local/bin/brew ]; then
    echo /usr/local
  elif [ "$(uname -m)" = "arm64" ]; then
    echo /opt/homebrew
  else
    echo /usr/local
  fi
}

# Put brew on PATH for the REST OF THIS PROCESS. The installer only edits shell
# profiles, so without this a bootstrap-then-install run in one invocation still
# cannot see the brew it just installed.
bs_brew_shellenv() {
  _bs_brew="$(bs_brew_prefix)/bin/brew"
  [ -x "$_bs_brew" ] || return 1
  eval "$("$_bs_brew" shellenv)" || return 1
  return 0
}

# Persist brew on PATH for future login shells (the installer prints this as a
# manual step). Idempotent: never appends a second time.
bs_brew_persist() {
  _bs_prefix="$(bs_brew_prefix)"
  _bs_line="eval \"\$($_bs_prefix/bin/brew shellenv)\""
  _bs_profile="$HOME/.zprofile"
  if [ -f "$_bs_profile" ] && grep -qF "brew shellenv" "$_bs_profile" 2>/dev/null; then
    bs_log "  brew shellenv already in $_bs_profile"
    return 0
  fi
  if [ -n "${BS_DRY_RUN:-}" ]; then
    bs_log "  DRY RUN: append 'brew shellenv' to $_bs_profile"
    return 0
  fi
  printf '\n# Added by ai-skills bootstrap\n%s\n' "$_bs_line" >> "$_bs_profile"
  bs_log "  added brew shellenv to $_bs_profile"
}

bs_ensure_brew() {
  [ -z "$BS_OS" ] && bs_detect_os
  if [ "$BS_OS" != "mac" ]; then
    return 0
  fi
  if bs_have brew; then
    bs_log "brew: already installed ($(command -v brew))"
    BS_PKG_MGR="brew"
    return 0
  fi
  # Installed but not on PATH (common in a fresh non-login shell).
  if bs_brew_shellenv && bs_have brew; then
    bs_log "brew: found at $(bs_brew_prefix), added to PATH for this run"
    BS_PKG_MGR="brew"
    return 0
  fi

  bs_log "brew: NOT installed -- macOS has no system package manager, so this is required"
  bs_log "  $BS_BREW_INSTALLER"
  bs_log "  (writes to $(bs_brew_prefix), needs sudo, and pulls Xcode Command Line Tools)"
  bs_confirm "  Install Homebrew now?" || return 1

  # NONINTERACTIVE stops the installer waiting on a RETURN we cannot supply.
  if [ -n "${BS_ASSUME_YES:-}" ]; then
    bs_run_sh "NONINTERACTIVE=1 $BS_BREW_INSTALLER" || return 1
  else
    bs_run_sh "$BS_BREW_INSTALLER" || return 1
  fi

  if [ -n "${BS_DRY_RUN:-}" ]; then
    BS_PKG_MGR="brew"
    return 0
  fi
  bs_brew_shellenv
  bs_brew_persist
  if bs_have brew; then
    bs_log "  brew installed at $(command -v brew)"
    BS_PKG_MGR="brew"
    return 0
  fi
  bs_die "Homebrew installer finished but brew is still not on PATH"
}

# ---------------------------------------------------------------------------
# zsh
# ---------------------------------------------------------------------------

# Highest-versioned zsh on this machine, or empty. Prints "<major> <path>".
bs_zsh_candidates() {
  for _bs_z in ${BS_ZSH_SEARCH:-/bin/zsh /usr/bin/zsh /usr/local/bin/zsh /opt/homebrew/bin/zsh} "$(command -v zsh 2>/dev/null)"; do
    [ -n "$_bs_z" ] || continue
    [ -x "$_bs_z" ] || continue
    _bs_ver="$("$_bs_z" -c 'echo ${ZSH_VERSION%%.*}' 2>/dev/null)"
    case "$_bs_ver" in
      ''|*[!0-9]*) continue ;;
    esac
    echo "$_bs_ver $_bs_z"
  done | sort -rnu
}

bs_ensure_zsh() {
  BS_ZSH=""
  if bs_have zsh; then
    BS_ZSH="$(command -v zsh)"
    bs_log "zsh: already installed ($BS_ZSH, $("$BS_ZSH" -c 'echo $ZSH_VERSION'))"
    return 0
  fi
  bs_log "zsh: not installed"
  bs_confirm "  Install zsh now?" || return 1
  bs_pkg_install zsh || return 1
  if [ -n "${BS_DRY_RUN:-}" ]; then
    # Nothing was installed, so there is no path to report. Do NOT invent one:
    # this used to hardcode /usr/bin/zsh (wrong on macOS, where it is /bin/zsh)
    # and a caller that re-exec'd BS_ZSH would exec something absent.
    BS_ZSH=""
    bs_log "  DRY RUN: zsh would be installed via ${BS_PKG_MGR:-the package manager}; no path to report yet"
    return 0
  fi
  hash -r 2>/dev/null || true
  if bs_have zsh; then
    BS_ZSH="$(command -v zsh)"
    bs_log "  zsh installed at $BS_ZSH"
    return 0
  fi
  bs_die "zsh install finished but zsh is still not on PATH"
}

# Which zsh should own the login shell.
#   system (default) -- a /bin or /usr/bin zsh if there is one. On macOS this
#     keeps /bin/zsh (5.9), which cannot be broken by removing Homebrew. A
#     login shell that lives in /opt/homebrew locks you out if that volume or
#     install ever goes away.
#   newest -- the highest version found, wherever it lives.
bs_preferred_login_zsh() {
  if [ "${BS_ZSH_PREFER:-system}" != "newest" ]; then
    for _bs_z in ${BS_SYSTEM_ZSH_SEARCH:-/bin/zsh /usr/bin/zsh}; do
      if [ -x "$_bs_z" ]; then
        echo "$_bs_z"
        return 0
      fi
    done
  fi
  bs_zsh_candidates | head -1 | cut -d' ' -f2-
}

# Make zsh the login shell. Requires the shell to be listed in /etc/shells.
bs_ensure_zsh_default() {
  if [ -n "${BS_NO_CHSH:-}" ]; then
    bs_log "login shell: BS_NO_CHSH set, leaving it alone"
    return 0
  fi
  _bs_target="$(bs_preferred_login_zsh)"
  if [ -z "$_bs_target" ]; then
    bs_warn "login shell: no zsh found to switch to"
    return 1
  fi

  _bs_current="$(bs_current_login_shell)"
  if [ "$_bs_current" = "$_bs_target" ]; then
    bs_log "login shell: already $_bs_target"
    return 0
  fi
  # Already a zsh, just a different one -- not worth a forced switch.
  case "$_bs_current" in
    */zsh)
      bs_log "login shell: already zsh ($_bs_current); leaving it (set BS_ZSH_PREFER=newest to move to $_bs_target)"
      return 0 ;;
  esac

  bs_log "login shell: $_bs_current -> $_bs_target"
  bs_ensure_in_etc_shells "$_bs_target" || return 1
  bs_confirm "  Change your login shell to $_bs_target?" || return 1
  bs_run $BS_SUDO chsh -s "$_bs_target" "$(id -un)" || {
    bs_warn "  chsh failed; run it yourself: sudo chsh -s $_bs_target $(id -un)"
    return 1
  }
  bs_log "  login shell set to $_bs_target (takes effect on next login)"
}

bs_current_login_shell() {
  if [ "$(uname -s)" = "Darwin" ] && bs_have dscl; then
    dscl . -read "/Users/$(id -un)" UserShell 2>/dev/null | awk '{print $2}'
  else
    getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7
  fi
}

# chsh refuses a shell that is not in /etc/shells.
bs_ensure_in_etc_shells() {
  _bs_shell="$1"
  if grep -qxF "$_bs_shell" /etc/shells 2>/dev/null; then
    return 0
  fi
  bs_log "  $_bs_shell is not in /etc/shells; chsh will refuse it"
  bs_confirm "  Add $_bs_shell to /etc/shells (needs sudo)?" || return 1
  bs_run_sh "echo '$_bs_shell' | $BS_SUDO tee -a /etc/shells >/dev/null" || return 1
  bs_log "  added $_bs_shell to /etc/shells"
}

# ---------------------------------------------------------------------------
# bash 4+
# ---------------------------------------------------------------------------
# skills/ai-setup/lib/ai-tools.sh needs associative arrays, so its two bash
# consumers (ai-setup.sh, battle_runner.sh) need bash 4+. macOS ships bash 3.2
# as /bin/bash and always will, for licensing reasons -- so on a Mac the only
# route to a modern bash is a package manager, which is why brew comes first.
# NOTE lib/spec_builder.sh is bash 3.2-clean and deliberately not covered here.

# Prints the path of the first bash >= BS_MIN_BASH_MAJOR, or nothing.
bs_find_bash() {
  for _bs_b in "$(command -v bash 2>/dev/null)" ${BS_BASH_SEARCH:-/opt/homebrew/bin/bash /usr/local/bin/bash /usr/bin/bash /bin/bash}; do
    [ -n "$_bs_b" ] || continue
    [ -x "$_bs_b" ] || continue
    _bs_maj="$("$_bs_b" -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null)"
    case "$_bs_maj" in
      ''|*[!0-9]*) continue ;;
    esac
    if [ "$_bs_maj" -ge "$BS_MIN_BASH_MAJOR" ]; then
      echo "$_bs_b"
      return 0
    fi
  done
  return 1
}

bs_ensure_bash() {
  BS_BASH=""
  if BS_BASH="$(bs_find_bash)"; then
    bs_log "bash: $BS_BASH ($("$BS_BASH" -c 'echo $BASH_VERSION'))"
    return 0
  fi
  bs_log "bash: none >= $BS_MIN_BASH_MAJOR found (system bash is $(/bin/bash -c 'echo $BASH_VERSION' 2>/dev/null))"
  bs_confirm "  Install a modern bash now?" || return 1
  bs_pkg_install bash || return 1
  if [ -n "${BS_DRY_RUN:-}" ]; then
    # As above: no invented path. This used to guess "$(bs_brew_prefix)/bin/bash"
    # regardless of OS, which is nonsense on Linux where apt installs to
    # /usr/bin/bash -- and the file does not exist either way during a dry run.
    BS_BASH=""
    bs_log "  DRY RUN: bash would be installed via ${BS_PKG_MGR:-the package manager}; no path to report yet"
    return 0
  fi
  hash -r 2>/dev/null || true
  if BS_BASH="$(bs_find_bash)"; then
    bs_log "  bash installed at $BS_BASH"
    return 0
  fi
  bs_die "bash install finished but no bash >= $BS_MIN_BASH_MAJOR is on PATH"
}

# ---------------------------------------------------------------------------
# Orchestration and re-exec helpers
# ---------------------------------------------------------------------------

# Full bootstrap, in dependency order: brew is the package manager that the
# zsh and bash installs depend on, so it goes first.
bs_bootstrap() {
  bs_detect_os
  bs_detect_pkg_mgr
  bs_log "os=$BS_OS pkg-manager=${BS_PKG_MGR:-none}"
  # Advisory, not fatal: a machine that already has brew, zsh and a modern bash
  # needs no root at all, and refusing there would be wrong.
  bs_check_sudo || bs_warn "  continuing; steps that need root will say so when they fail"
  _bs_rc=0
  bs_ensure_brew || _bs_rc=1
  bs_detect_pkg_mgr
  bs_ensure_zsh  || _bs_rc=1
  bs_ensure_bash || _bs_rc=1
  bs_ensure_zsh_default || _bs_rc=1
  return "$_bs_rc"
}

# Re-exec a bash script under a bash 4+, installing one first if needed.
bs_exec_bash() {
  _bs_script="$1"
  shift
  [ -f "$_bs_script" ] || { bs_die "no such script: $_bs_script"; return 1; }
  if ! BS_BASH="$(bs_find_bash)"; then
    bs_detect_os
    bs_detect_pkg_mgr
    bs_ensure_brew || return 1
    bs_detect_pkg_mgr
    bs_ensure_bash || return 1
  fi
  # Refuse rather than exec something absent. Under BS_DRY_RUN nothing was
  # installed, so BS_BASH is deliberately empty; previously this branch invented
  # a path and exec'd it, turning a clear refusal into "exec: not found".
  if [ -z "$BS_BASH" ] || [ ! -x "$BS_BASH" ]; then
    bs_warn "cannot run $(basename "$_bs_script"): no bash >= $BS_MIN_BASH_MAJOR available."
    if [ -n "${BS_DRY_RUN:-}" ]; then
      bs_warn "  BS_DRY_RUN is set, so nothing was installed and there is nothing to run under."
      bs_warn "  Re-run without BS_DRY_RUN to install one."
    else
      bs_warn "  Install one (brew install bash / apt install bash) and retry."
    fi
    return 1
  fi
  exec "$BS_BASH" "$_bs_script" "$@"
}
