#!/usr/bin/env zsh
# Shared helpers for machine-setup.
#
# backup_path and ensure_dir now live in lib/fs-helpers.sh (POSIX sh) so the
# bash side (ai-setup.sh) and the zsh side (machine-setup) share ONE
# implementation. They used to be typed out twice with different timestamp
# variables, and this file's zsh-only `(( $+functions[log] ))` meant bash could
# not have converged on it. THE_SPEC forbids that duplication and TICKET-SPEC
# Req 9 asks for reuse of ai-setup's pattern, not a copy of it.
#
# This file is kept as the stable include point for machine-setup.

: "${REPO_ROOT:?REPO_ROOT must be set before sourcing lib/setup-helpers.zsh}"
source "$REPO_ROOT/lib/fs-helpers.sh"
