#!/usr/bin/env bash
set -euo pipefail

# Create COSMIC/GNOME desktop launchers backed by the vendors' official web apps.
# This deliberately avoids unofficial Linux wrappers. Claude Desktop and Grok Bot
# do not currently publish official Linux desktop binaries.

INSTALL_CLAUDE=true
INSTALL_CHATGPT=true
INSTALL_GROK=true
DRY_RUN=false

log() { printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Creates application-menu entries that open official AI web apps in a dedicated
Chromium/Chrome window.

Options:
  --only <app>   Install only claude, chatgpt, or grok (repeatable)
  --no-claude    Skip Claude
  --no-chatgpt   Skip ChatGPT
  --no-grok      Skip Grok
  --dry-run      Show what would be created
  -h, --help     Show this help
EOF
}

ONLY_SET=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)
      [[ $# -ge 2 ]] || die "--only requires claude, chatgpt, or grok"
      if [[ "$ONLY_SET" == false ]]; then
        INSTALL_CLAUDE=false; INSTALL_CHATGPT=false; INSTALL_GROK=false; ONLY_SET=true
      fi
      case "$2" in
        claude) INSTALL_CLAUDE=true ;;
        chatgpt) INSTALL_CHATGPT=true ;;
        grok) INSTALL_GROK=true ;;
        *) die "Unknown app for --only: $2" ;;
      esac
      shift 2
      ;;
    --no-claude) INSTALL_CLAUDE=false; shift ;;
    --no-chatgpt) INSTALL_CHATGPT=false; shift ;;
    --no-grok) INSTALL_GROK=false; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

find_browser() {
  local candidate
  for candidate in google-chrome-stable google-chrome chromium chromium-browser; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return
    fi
  done
  return 1
}

create_launcher() {
  local slug="$1" name="$2" url="$3" icon="$4"
  local applications_dir="$HOME/.local/share/applications"
  local desktop_file="$applications_dir/$slug.desktop"
  local profile_dir="$HOME/.local/share/ai-desktop-apps/$slug"

  if [[ "$DRY_RUN" == true ]]; then
    printf 'Would create %s -> %s\n' "$desktop_file" "$url"
    return
  fi

  mkdir -p "$applications_dir" "$profile_dir"
  cat > "$desktop_file" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$name
Comment=$name official web app
Exec=$BROWSER --app=$url --user-data-dir=$profile_dir
Icon=$icon
Terminal=false
Categories=Network;Development;
StartupNotify=true
StartupWMClass=$slug
EOF
  chmod 0644 "$desktop_file"
  log "Created $name launcher"
}

main() {
  [[ "${EUID:-$(id -u)}" -ne 0 ]] || die "Run this script as your normal user, not with sudo."
  BROWSER="$(find_browser || true)"
  if [[ -z "$BROWSER" && "$DRY_RUN" == true ]]; then
    BROWSER="/path/to/google-chrome-or-chromium"
  fi
  [[ -n "$BROWSER" ]] || die "Install Google Chrome or Chromium first (install-chrome-stylus-catppuccin.sh can install Chrome)."

  [[ "$INSTALL_CLAUDE" == true ]] && create_launcher "claude" "Claude" "https://claude.ai/" "web-browser"
  [[ "$INSTALL_CHATGPT" == true ]] && create_launcher "chatgpt" "ChatGPT" "https://chatgpt.com/" "web-browser"
  [[ "$INSTALL_GROK" == true ]] && create_launcher "grok" "Grok" "https://grok.com/" "web-browser"

  if [[ "$DRY_RUN" == false ]] && command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$HOME/.local/share/applications" || true
  fi
  log "Desktop launcher installation complete"
}

main
