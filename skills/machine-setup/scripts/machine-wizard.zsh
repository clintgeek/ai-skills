#!/usr/bin/env zsh
# machine-wizard: interview-driven new-machine bootstrap.
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h}"

source "$REPO_ROOT/lib/machine-setup.zsh"

ROLE=""
CATEGORIES=""
EXTRAS=""
YES=false
DRY_RUN=false
REPOS_ONLY=false
AI=false

SELECTED_APPS=()
INSTALLED=()
SKIPPED=()
FAILED=()
VALID_ROLES=(dev admin general)

usage() {
  cat << 'EOF'
Usage: machine-wizard.zsh [options]

Options:
  --role <role>          Primary role: dev, admin, general
  --categories <list>    Comma-separated categories
  --extras <list>        Comma-separated app ids to force-include
  --ai                   Also install and hotwire known AI CLIs
  --yes                  Run without prompting
  --dry-run              Show plan, do not execute
  --repos-only           Set up personal repos only, skip app installs
  -h, --help             Show this message
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --role)
        [[ $# -lt 2 ]] && { echo "Error: --role requires an argument" >&2; exit 1; }
        ROLE="$2"; shift 2 ;;
      --categories)
        [[ $# -lt 2 ]] && { echo "Error: --categories requires an argument" >&2; exit 1; }
        CATEGORIES="$2"; shift 2 ;;
      --extras)
        [[ $# -lt 2 ]] && { echo "Error: --extras requires an argument" >&2; exit 1; }
        EXTRAS="$2"; shift 2 ;;
      --ai) AI=true; shift ;;
      --yes) YES=true; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      --repos-only) REPOS_ONLY=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
  done
}

valid_role() {
  local r="$1" v
  for v in "${VALID_ROLES[@]}"; do
    [[ "$v" == "$r" ]] && return 0
  done
  return 1
}

run_interview() {
  if [[ -t 0 && "$REPOS_ONLY" != true && "$YES" != true ]]; then
    if [[ -z "$ROLE" ]]; then
      printf "%s" "Primary role? (dev/admin/general) "
      read -r ROLE || true
    fi
    if [[ -z "$CATEGORIES" ]]; then
      printf "%s" "Categories? (comma-separated: cli,terminal,browser,productivity,security,media,dev-tools,cloud,communication) "
      read -r CATEGORIES || true
    fi
  fi
  if [[ "$REPOS_ONLY" == true ]]; then
    return 0
  fi
  if [[ -z "$ROLE" || -z "$CATEGORIES" ]]; then
    echo "Error: --role and --categories are required." >&2
    usage >&2
    exit 1
  fi
  if ! valid_role "$ROLE"; then
    echo "Error: --role must be one of: ${VALID_ROLES[*]}" >&2
    usage >&2
    exit 1
  fi
}

edit_checklist() {
  [[ "$YES" == true ]] && return 0
  [[ -t 0 ]] || return 0
  echo ""
  echo "Selected apps:"
  show_checklist
  printf "%s" "Numbers to remove (comma-separated), or Enter to keep all: "
  local remove_s
  read -r remove_s || true
  [[ -z "$remove_s" ]] && return 0
  local to_remove=( ${(s:,:)remove_s} )
  local -a new=()
  local i=1 app n remove
  for app in "${SELECTED_APPS[@]}"; do
    remove=false
    for n in $to_remove; do
      [[ "$n" == "$i" ]] && remove=true
    done
    [[ "$remove" != true ]] && new+=("$app")
    ((i++))
  done
  SELECTED_APPS=("${new[@]}")
}

show_checklist() {
  local i=1 app
  for app in "${SELECTED_APPS[@]}"; do
    printf "%2d. %s\n" "$i" "${APP_NAME[$app]:-$app}"
    ((i++))
  done
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

print_plan() {
  echo ""
  echo "=== Plan ==="
  local id path post ts
  for id in "${MACHINE_REPOS[@]}"; do
    path="${REPO_PATH[$id]:-}"
    [[ -z "$path" ]] && continue
    post="${REPO_POST_CLONE[$id]:-}"
    if [[ -n "${REPO_ROOT:-}" && "$path" == "$REPO_ROOT" ]]; then
      echo "  skip active repo ${REPO_NAME[$id]:-$id} -> $path"
      continue
    fi
    if [[ -d "$path/.git" ]]; then
      echo "  pull ${REPO_NAME[$id]:-$id} -> $path"
    elif [[ -e "$path" || -L "$path" ]]; then
      ts="${BACKUP_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
      echo "  back up ${REPO_NAME[$id]:-$id} -> $path to ${path}.bak-${ts}, then clone"
      [[ -n "$post" ]] && echo "    then run $post"
    else
      echo "  clone ${REPO_NAME[$id]:-$id} -> $path"
      [[ -n "$post" ]] && echo "    then run $post"
    fi
  done
  local app cmd
  for app in "${SELECTED_APPS[@]}"; do
    cmd="$(install_cmd "$app")"
    if [[ -n "$cmd" ]]; then
      echo "  install ${APP_NAME[$app]:-$app}: $cmd"
    elif [[ "$app" == *" "* ]]; then
      echo "  install raw: $app"
    else
      echo "  skip $app (no $OS_KIND installer)"
    fi
  done
  if [[ "$AI" == true && "$REPOS_ONLY" != true ]]; then
    local tool ai_cmd
    for tool in "${AI_TOOLS[@]}"; do
      if [[ "${TOOL_KNOWN[$tool]:-0}" -eq 1 ]]; then
        ai_cmd="$(install_command "$tool")"
        [[ -n "$ai_cmd" ]] && echo "  install AI CLI ${TOOL_NAME[$tool]:-$tool}: $ai_cmd"
        echo "  hotwire AI CLI ${TOOL_NAME[$tool]:-$tool}"
        echo "    back up ${TOOL_LAWS[$tool]:-$tool}, symlink laws -> ${AI_LAWS:-$HOME/.ai/laws}/global_rules.md"
        echo "    back up ${TOOL_SKILLS[$tool]:-$tool}, symlink skills -> ${AI_SKILLS:-$HOME/.ai}"
      fi
    done
  fi
}

execute_plan() {
  setup_repos
  [[ "$REPOS_ONLY" == true ]] && return 0
  local app cmd
  log "installing apps..."
  for app in "${SELECTED_APPS[@]}"; do
    cmd="$(install_cmd "$app")"
    if [[ -z "$cmd" && "$app" == *" "* ]]; then
      cmd="$app"
    fi
    if [[ -z "$cmd" ]]; then
      log "  $app: no $OS_KIND installer, skipping"
      SKIPPED+=("$app")
      continue
    fi
    log "  installing ${APP_NAME[$app]:-$app}..."
    if eval "$cmd"; then
      INSTALLED+=("$app")
    else
      FAILED+=("$app")
      log "  failed to install $app"
    fi
  done
  if [[ "$AI" == true ]]; then
    setup_ai_clis
  fi
}

report() {
  echo ""
  echo "=== machine-setup report ==="
  echo "Installed: ${#INSTALLED[@]} ${INSTALLED[*]}"
  echo "Skipped:   ${#SKIPPED[@]} ${SKIPPED[*]}"
  echo "Failed:    ${#FAILED[@]} ${FAILED[*]}"
}

main() {
  parse_args "$@"
  if [[ "$AI" == true && "$REPOS_ONLY" == true ]]; then
    log "--ai is ignored with --repos-only"
    AI=false
  fi
  if [[ "$DRY_RUN" == true && "$REPOS_ONLY" != true && ( -z "$ROLE" || -z "$CATEGORIES" ) ]]; then
    ROLE="${ROLE:-general}"
    CATEGORIES="${CATEGORIES:-cli}"
  fi
  run_interview
  if [[ "$REPOS_ONLY" != true ]]; then
    preselect_apps "$ROLE" "$CATEGORIES" "$EXTRAS"
  fi
  edit_checklist
  print_plan
  if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run, not executing."
    exit 0
  fi
  confirm_run
  execute_plan
  report
  if [[ ${#FAILED[@]} -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
