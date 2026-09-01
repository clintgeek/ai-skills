#!/usr/bin/env zsh
# machine-wizard: interview-driven new-machine bootstrap.
#
# Invoke via scripts/machine-wizard (the sh wrapper), which guarantees brew,
# zsh, a modern bash, and zsh as the login shell before this runs.
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h:h}"

source "$REPO_ROOT/lib/machine-setup.zsh"

ROLES=""
CATEGORIES=""
YES=false
DRY_RUN=false
REPOS_ONLY=false
AI=false
AI_INSTALL=false

typeset -a EXTRAS RAW_CMDS SELECTED_APPS INSTALLED ALREADY SKIPPED FAILED
EXTRAS=(); RAW_CMDS=(); SELECTED_APPS=(); INSTALLED=(); ALREADY=(); SKIPPED=(); FAILED=()

# Roles from DOCS/TICKET-SPEC.md Req 5. Every one of these must carry apps in
# lib/app-catalog.zsh, or it selects nothing but `base`; checked below and
# asserted in lib/tests/machine_setup_test.zsh.
VALID_ROLES=(dev design data writing gaming admin general)
VALID_CATEGORIES=(cli terminal browser productivity security media dev-tools cloud communication base)

usage() {
  cat << 'EOF'
Usage: machine-wizard [options]

Options:
  --role <list>          Comma-separated roles: dev, design, data, writing,
                         gaming, admin, general
  --categories <list>    Comma-separated categories: cli, terminal, browser,
                         productivity, security, media, dev-tools, cloud,
                         communication
  --extras <list>        Comma-separated app ids or package names to add.
                         Repeatable. Unknown names are installed as packages
                         via the local package manager.
  --extra-cmd <command>  A raw install command, run verbatim. Repeatable.
                         Never split, so commas and shell syntax are safe.
  --ai                   Hotwire the known AI CLIs that are ALREADY installed
  --ai-install           Also run the installer for missing AI CLIs (implies
                         --ai; each installer is a vendor script, so this is
                         opt-in rather than part of --ai)
  --yes                  Run without prompting
  --dry-run              Show plan, do not execute
  --repos-only           Set up personal repos only, skip app installs
  -h, --help             Show this message

Notes:
  --extras is a comma-separated list of NAMES (`--extras neovim,ripgrep`), so a
  comma is a separator and cannot appear inside an entry. A single entry with
  shell syntax or whitespace is still detected and run verbatim
  (`--extras 'brew install x'`), but anything containing a comma must use
  --extra-cmd, which is never split:
      --extra-cmd 'brew tap a/b, brew install c'
  Unknown names are installed as packages via the local package manager.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --role|--roles)
        [[ $# -lt 2 ]] && { echo "Error: $1 requires an argument" >&2; exit 1; }
        ROLES="$2"; shift 2 ;;
      --categories)
        [[ $# -lt 2 ]] && { echo "Error: --categories requires an argument" >&2; exit 1; }
        CATEGORIES="$2"; shift 2 ;;
      --extras)
        [[ $# -lt 2 ]] && { echo "Error: --extras requires an argument" >&2; exit 1; }
        # --extras is a COMMA-DELIMITED NAME LIST, so a comma is a separator and
        # can never be data. A value that both contains a comma and looks like a
        # shell command is ambiguous: splitting it would eval the fragments
        # separately (the original bug), and not splitting it would break plain
        # name lists. Refuse it and name the flag that does the right thing.
        if [[ "$2" == *,* && ( "$2" == *[\|\&\;\$\(\)\<\>\*\"\']* || "$2" == *' '*[^' ']*' '* ) ]]; then
          echo "Error: --extras is a comma-separated list of app ids/package names," >&2
          echo "       so a comma cannot appear inside one entry. This value looks like" >&2
          echo "       a shell command:" >&2
          echo "         $2" >&2
          echo "       Pass commands verbatim with --extra-cmd instead:" >&2
          echo "         --extra-cmd '$2'" >&2
          exit 1
        fi
        local e
        for e in ${(s:,:)2}; do
          e="${e## }"; e="${e%% }"
          [[ -n "$e" ]] && EXTRAS+=("$e")
        done
        shift 2 ;;
      --extra-cmd)
        [[ $# -lt 2 ]] && { echo "Error: --extra-cmd requires an argument" >&2; exit 1; }
        RAW_CMDS+=("$2"); shift 2 ;;
      --ai) AI=true; shift ;;
      --ai-install) AI=true; AI_INSTALL=true; shift ;;
      --yes) YES=true; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      --repos-only) REPOS_ONLY=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
  done
}

in_list() {  # in_list <needle> <haystack...>
  local needle="$1"; shift
  local v
  for v in "$@"; do
    [[ "$v" == "$needle" ]] && return 0
  done
  return 1
}

validate_roles() {
  local r bad=()
  for r in ${(s:,:)ROLES}; do
    [[ -z "$r" ]] && continue
    if ! in_list "$r" "${VALID_ROLES[@]}"; then
      bad+=("$r")
      continue
    fi
    # A role with no apps would silently contribute nothing -- surface it
    # rather than letting the user think it did something.
    if [[ "$(role_app_count "$r")" -eq 0 ]]; then
      log "warning: role '$r' matches no apps in the catalog; it adds nothing beyond the base set"
    fi
  done
  if (( ${#bad[@]} > 0 )); then
    echo "Error: unknown role(s): ${bad[*]}" >&2
    echo "Valid roles: ${VALID_ROLES[*]}" >&2
    exit 1
  fi
}

validate_categories() {
  local c bad=()
  for c in ${(s:,:)CATEGORIES}; do
    [[ -z "$c" ]] && continue
    in_list "$c" "${VALID_CATEGORIES[@]}" || bad+=("$c")
  done
  if (( ${#bad[@]} > 0 )); then
    echo "Error: unknown categor(ies): ${bad[*]}" >&2
    echo "Valid categories: ${VALID_CATEGORIES[*]}" >&2
    exit 1
  fi
}

run_interview() {
  if [[ -t 0 && "$REPOS_ONLY" != true && "$YES" != true ]]; then
    if [[ -z "$ROLES" ]]; then
      printf "%s" "Primary role(s)? (comma-separated: ${(j:/:)VALID_ROLES}) "
      read -r ROLES || true
    fi
    if [[ -z "$CATEGORIES" ]]; then
      printf "%s" "Categories? (comma-separated: cli,terminal,browser,productivity,security,media,dev-tools,cloud,communication) "
      read -r CATEGORIES || true
    fi
  fi
  [[ "$REPOS_ONLY" == true ]] && return 0
  if [[ -z "$ROLES" || -z "$CATEGORIES" ]]; then
    echo "Error: --role and --categories are required." >&2
    usage >&2
    exit 1
  fi
  validate_roles
  validate_categories
}

# ---------------------------------------------------------------------------
# Interactive checklist: toggle on/off, add names or raw commands
# ---------------------------------------------------------------------------
typeset -a CHECK_ITEMS CHECK_ON
CHECK_ITEMS=(); CHECK_ON=()

checklist_load() {
  CHECK_ITEMS=(); CHECK_ON=()
  local item
  for item in "${SELECTED_APPS[@]}"; do
    CHECK_ITEMS+=("$item")
    CHECK_ON+=("1")
  done
}

checklist_commit() {
  SELECTED_APPS=()
  local i
  for i in {1..${#CHECK_ITEMS[@]}}; do
    [[ "${CHECK_ON[$i]}" == "1" ]] && SELECTED_APPS+=("${CHECK_ITEMS[$i]}")
  done
}

show_checklist() {
  local i mark
  for i in {1..${#CHECK_ITEMS[@]}}; do
    [[ "${CHECK_ON[$i]}" == "1" ]] && mark="x" || mark=" "
    printf "  [%s] %2d. %s\n" "$mark" "$i" "$(item_label "${CHECK_ITEMS[$i]}")"
  done
  local on=0
  for i in {1..${#CHECK_ITEMS[@]}}; do
    # NOT (( on++ )): see lib/machine-setup.zsh role_app_count. Post-increment
    # from 0 evaluates to 0, which `set -e` reads as failure and kills the run
    # mid-checklist.
    [[ "${CHECK_ON[$i]}" == "1" ]] && on=$(( on + 1 ))
  done
  echo "  ($on of ${#CHECK_ITEMS[@]} selected)"
}

checklist_help() {
  cat << 'EOF'

  <numbers>   toggle items on/off   (e.g. "3" or "3,7 9")
  +<name>     add an app id or package name  (e.g. "+neovim")
  +<command>  add a raw install command      (e.g. "+brew tap a/b && brew install c")
  all / none  select or deselect everything
  list        redisplay
  help        show these commands
  done        finish (or just press Enter)
EOF
}

checklist_toggle() {
  local n="$1"
  if [[ "$n" != <-> ]] || (( n < 1 || n > ${#CHECK_ITEMS[@]} )); then
    echo "  ? no item $n (valid range: 1-${#CHECK_ITEMS[@]})"
    return 0
  fi
  [[ "${CHECK_ON[$n]}" == "1" ]] && CHECK_ON[$n]="0" || CHECK_ON[$n]="1"
}

checklist_add() {
  local raw="$1" item
  item="$(classify_extra "$raw")" || { echo "  ? nothing to add"; return 0; }
  local i
  for i in {1..${#CHECK_ITEMS[@]}}; do
    if [[ "${CHECK_ITEMS[$i]}" == "$item" ]]; then
      CHECK_ON[$i]="1"
      echo "  already listed as #$i; selected it"
      return 0
    fi
  done
  CHECK_ITEMS+=("$item")
  CHECK_ON+=("1")
  echo "  added #${#CHECK_ITEMS[@]}: $(item_label "$item")"
}

edit_checklist() {
  [[ "$YES" == true ]] && return 0
  # MACHINE_WIZARD_FORCE_INTERACTIVE lets the test suite drive this loop over a
  # plain pipe. Driving it through a real pty (script(1)) loses input lines
  # nondeterministically, which makes the tests flaky rather than wrong.
  [[ -t 0 || -n "${MACHINE_WIZARD_FORCE_INTERACTIVE:-}" ]] || return 0
  [[ "$REPOS_ONLY" == true ]] && return 0
  echo ""
  echo "Selected apps:"
  show_checklist
  checklist_help
  local line rest tok
  while true; do
    printf "%s" "> "
    read -r line || break
    line="${line## }"; line="${line%% }"
    case "$line" in
      ""|done|d|q|quit) break ;;
      list|l) show_checklist ;;
      all|a)
        local i
        for i in {1..${#CHECK_ITEMS[@]}}; do CHECK_ON[$i]="1"; done
        show_checklist ;;
      none|n)
        local i
        for i in {1..${#CHECK_ITEMS[@]}}; do CHECK_ON[$i]="0"; done
        show_checklist ;;
      \+*)
        rest="${line#+}"
        rest="${rest## }"
        checklist_add "$rest" ;;
      help|\?) checklist_help ;;
      *)
        # Item numbers, separated by commas and/or whitespace. Every token has
        # to be numeric: a non-numeric token is unrecognized input, not a
        # missing item number, and saying "no item zzz" for it is misleading.
        local -a toks
        toks=( ${(s:,:)${line//[[:space:]]/,}} )
        local all_numeric=true
        for tok in $toks; do
          [[ -z "$tok" ]] && continue
          [[ "$tok" == <-> ]] || all_numeric=false
        done
        if [[ "$all_numeric" != true ]]; then
          echo "  ? unrecognized: $line   (type 'help' for commands)"
          continue
        fi
        for tok in $toks; do
          [[ -n "$tok" ]] && checklist_toggle "$tok"
        done
        show_checklist ;;
    esac
  done
  checklist_commit
}

print_plan() {
  echo ""
  echo "=== Plan ==="
  # NOT `path`: see setup_repos in lib/machine-setup.zsh. zsh ties `path` to
  # PATH, and clobbering it here made the `command -v` checks below report every
  # installed AI CLI as missing.
  local id repo_path post ts
  for id in "${MACHINE_REPOS[@]}"; do
    repo_path="${REPO_PATH[$id]:-}"
    [[ -z "$repo_path" ]] && continue
    post="${REPO_POST_CLONE[$id]:-}"
    if [[ -n "${REPO_ROOT:-}" && "$repo_path" == "$REPO_ROOT" ]]; then
      echo "  skip active repo ${REPO_NAME[$id]:-$id} -> $repo_path"
      continue
    fi
    if [[ -d "$repo_path/.git" ]]; then
      echo "  pull ${REPO_NAME[$id]:-$id} -> $repo_path"
    elif [[ -e "$repo_path" || -L "$repo_path" ]]; then
      ts="${BACKUP_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
      echo "  back up ${REPO_NAME[$id]:-$id} -> $repo_path to ${repo_path}.bak-${ts}, then clone"
      [[ -n "$post" ]] && echo "    then run $post"
    else
      echo "  clone ${REPO_NAME[$id]:-$id} -> $repo_path"
      [[ -n "$post" ]] && echo "    then run $post"
    fi
  done
  local item cmd
  for item in "${SELECTED_APPS[@]}"; do
    cmd="$(item_install_cmd "$item")"
    if [[ -z "$cmd" ]]; then
      echo "  skip $(item_label "$item") (no $OS_KIND installer)"
    elif item_is_installed "$item"; then
      echo "  install $(item_label "$item"): $cmd   [already installed — will skip]"
    else
      echo "  install $(item_label "$item"): $cmd"
    fi
  done
  if [[ "$AI" == true && "$REPOS_ONLY" != true ]]; then
    local tool ai_cmd
    for tool in "${AI_TOOLS[@]}"; do
      if [[ "${TOOL_KNOWN[$tool]:-0}" -eq 1 ]]; then
        if ! command -v "$tool" >/dev/null 2>&1; then
          if [[ "$AI_INSTALL" != true ]]; then
            echo "  skip AI CLI ${TOOL_NAME[$tool]:-$tool} (not installed; --ai-install to install)"
            continue
          fi
          ai_cmd="$(install_command "$tool")"
          [[ -n "$ai_cmd" ]] && echo "  install AI CLI ${TOOL_NAME[$tool]:-$tool}: $ai_cmd"
        fi
        echo "  hotwire AI CLI ${TOOL_NAME[$tool]:-$tool}"
        echo "    back up ${TOOL_LAWS[$tool]:-$tool}, symlink laws -> ${AI_LAWS:-$HOME/.ai/laws}/global_rules.md"
        echo "    back up ${TOOL_SKILLS[$tool]:-$tool}, symlink skills -> ${AI_SKILLS:-$HOME/.ai/skills}"
      fi
    done
  fi
}

confirm_run() {
  [[ "$YES" == true ]] && return 0
  if [[ ! -t 0 ]]; then
    echo ""
    echo "Non-interactive: run again with --yes to execute this plan."
    exit 0
  fi
  local a
  printf "%s" "Run this plan? [y/N] "
  read -r a || true
  [[ "$a" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
}

execute_plan() {
  setup_repos
  [[ "$REPOS_ONLY" == true ]] && return 0
  local item cmd
  log "installing apps..."
  for item in "${SELECTED_APPS[@]}"; do
    cmd="$(item_install_cmd "$item")"
    if [[ -z "$cmd" ]]; then
      log "  $(item_label "$item"): no $OS_KIND installer, skipping"
      SKIPPED+=("$item")
      continue
    fi
    if item_is_installed "$item"; then
      log "  $(item_label "$item"): already installed, skipping"
      ALREADY+=("$item")
      continue
    fi
    log "  installing $(item_label "$item")..."
    if eval "$cmd"; then
      INSTALLED+=("$item")
    else
      FAILED+=("$item")
      log "  failed to install $(item_label "$item")"
    fi
  done
  [[ "$AI" == true ]] && setup_ai_clis "$AI_INSTALL"
  return 0
}

report() {
  echo ""
  echo "=== machine-setup report ==="
  local item
  printf "Installed: %d\n" "${#INSTALLED[@]}"
  for item in "${INSTALLED[@]}"; do echo "  + $(item_label "$item")"; done
  printf "Already:   %d\n" "${#ALREADY[@]}"
  for item in "${ALREADY[@]}"; do echo "  = $(item_label "$item")"; done
  printf "Skipped:   %d\n" "${#SKIPPED[@]}"
  for item in "${SKIPPED[@]}"; do echo "  - $(item_label "$item")"; done
  printf "Failed:    %d\n" "${#FAILED[@]}"
  for item in "${FAILED[@]}"; do echo "  ! $(item_label "$item")"; done
}

main() {
  parse_args "$@"
  if [[ "$AI" == true && "$REPOS_ONLY" == true ]]; then
    log "--ai/--ai-install is ignored with --repos-only"
    AI=false
    AI_INSTALL=false
  fi
  if [[ "$DRY_RUN" == true && "$REPOS_ONLY" != true && ( -z "$ROLES" || -z "$CATEGORIES" ) ]]; then
    ROLES="${ROLES:-general}"
    CATEGORIES="${CATEGORIES:-cli}"
  fi
  run_interview
  if [[ "$REPOS_ONLY" != true ]]; then
    preselect_apps "$ROLES" "$CATEGORIES"
    (( ${#EXTRAS[@]} > 0 ))   && add_extras "${EXTRAS[@]}"
    # Raw commands bypass classification entirely -- they are commands by
    # declaration, so nothing can reinterpret them as a name.
    local c
    for c in "${RAW_CMDS[@]}"; do
      (( ! ${SELECTED_APPS[(Ie)cmd:$c]} )) && SELECTED_APPS+=("cmd:$c")
    done
  fi
  checklist_load
  edit_checklist
  print_plan
  if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run, not executing."
    exit 0
  fi
  confirm_run
  execute_plan
  report
  (( ${#FAILED[@]} > 0 )) && exit 1
  return 0
}

main "$@"
