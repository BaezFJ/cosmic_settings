#!/usr/bin/env bash
set -euo pipefail

# Import the repository's light and dark themes through COSMIC Settings' supported
# command-line interface. The preferred theme is imported last so it stays active.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
DARK_THEME="$REPO_ROOT/system/theme/Catppuccin Macchiato Lavender (Dark).ron"
LIGHT_THEME="$REPO_ROOT/system/theme/Catppuccin Latte Lavender (Light).ron"

PREFERRED_MODE="dark"
DRY_RUN=false

log() { printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Imports both repository themes and leaves the selected mode active.

Options:
  --dark       Leave Catppuccin Macchiato active (default)
  --light      Leave Catppuccin Latte active
  --dry-run    Print imports without changing COSMIC settings
  -h, --help   Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dark) PREFERRED_MODE="dark"; shift ;;
    --light) PREFERRED_MODE="light"; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

import_theme() {
  local theme_file="$1"
  if [[ "$DRY_RUN" == true ]]; then
    printf 'Would import: %s\n' "$theme_file"
  else
    cosmic-settings appearance import "$theme_file"
  fi
}

main() {
  [[ "${EUID:-$(id -u)}" -ne 0 ]] || die "Run this script as your logged-in desktop user, not with sudo."
  [[ -r "$DARK_THEME" ]] || die "Dark theme not found: $DARK_THEME"
  [[ -r "$LIGHT_THEME" ]] || die "Light theme not found: $LIGHT_THEME"

  if [[ "$DRY_RUN" == false ]]; then
    command -v cosmic-settings >/dev/null 2>&1 || die "cosmic-settings is not installed."
    cosmic-settings appearance import --help >/dev/null 2>&1 \
      || die "This COSMIC Settings version does not support command-line theme imports."
  fi

  log "Importing COSMIC Catppuccin themes"
  if [[ "$PREFERRED_MODE" == "dark" ]]; then
    import_theme "$LIGHT_THEME"
    import_theme "$DARK_THEME"
  else
    import_theme "$DARK_THEME"
    import_theme "$LIGHT_THEME"
  fi

  log "COSMIC themes configured; active preference: $PREFERRED_MODE"
}

main
