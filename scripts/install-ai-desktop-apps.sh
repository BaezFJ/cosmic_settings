#!/usr/bin/env bash
set -euo pipefail

# Install official native desktop packages when Linux is supported, and create
# COSMIC/GNOME launchers for official web apps otherwise. No unofficial wrappers.

CLAUDE_KEY_URL="https://downloads.claude.ai/claude-desktop/key.asc"
CLAUDE_KEYRING="/usr/share/keyrings/claude-desktop-archive-keyring.asc"
CLAUDE_SOURCE_LIST="/etc/apt/sources.list.d/claude-desktop.list"
CLAUDE_REPOSITORY="https://downloads.claude.ai/claude-desktop/apt/stable"
CLAUDE_KEY_FINGERPRINT="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"
GROK_BOT_DOWNLOAD_URL="https://api2.cursor.sh/updates/download/stable/linux-x64/grok-bot-fb0a830618be0c54"

INSTALL_CLAUDE=true
INSTALL_CHATGPT=true
INSTALL_GROK=true
DRY_RUN=false

log() { printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Installs the official Claude Desktop and Grok Bot Linux betas and creates an
application-menu entry for ChatGPT's official web app.

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

run_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die "sudo is required to install Claude Desktop"
  fi
}

install_claude_desktop() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '%s\n' "Would add Anthropic's signed apt repository and install claude-desktop"
    return
  fi

  command -v apt-get >/dev/null 2>&1 || die "Claude Desktop requires an apt-based distribution."
  command -v dpkg >/dev/null 2>&1 || die "dpkg is required to check the system architecture."

  local architecture temp_dir key_file fingerprint source_line
  architecture="$(dpkg --print-architecture)"
  case "$architecture" in
    amd64|arm64) ;;
    *) die "Claude Desktop supports only amd64 and arm64; detected $architecture." ;;
  esac

  log "Installing Claude Desktop repository prerequisites"
  run_root apt-get update
  run_root apt-get install -y ca-certificates curl gnupg

  temp_dir="$(mktemp -d)"
  trap "rm -rf '$temp_dir'" EXIT
  key_file="$temp_dir/claude-desktop-key.asc"
  curl -fsSLo "$key_file" "$CLAUDE_KEY_URL"

  fingerprint="$(gpg --batch --show-keys --with-colons "$key_file" | awk -F: '$1 == "fpr" { print $10; exit }')"
  [[ "$fingerprint" == "$CLAUDE_KEY_FINGERPRINT" ]] || die "Anthropic signing-key fingerprint verification failed."

  run_root install -d -m 0755 /usr/share/keyrings /etc/apt/sources.list.d
  run_root install -m 0644 "$key_file" "$CLAUDE_KEYRING"
  source_line="deb [arch=amd64,arm64 signed-by=$CLAUDE_KEYRING] $CLAUDE_REPOSITORY stable main"
  printf '%s\n' "$source_line" | run_root tee "$CLAUDE_SOURCE_LIST" >/dev/null

  log "Installing Claude Desktop Linux beta"
  run_root apt-get update
  run_root apt-get install -y claude-desktop
  command -v claude-desktop >/dev/null 2>&1 || die "claude-desktop was installed but is not on PATH"
  rm -rf "$temp_dir"
  trap - EXIT
  log "Installed Claude Desktop"
}

install_grok_bot() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '%s\n' "Would download, verify, and install the official Grok Bot amd64 .deb"
    return
  fi

  command -v apt-get >/dev/null 2>&1 || die "Grok Bot requires an apt-based distribution."
  command -v dpkg >/dev/null 2>&1 || die "dpkg is required to check the system architecture."
  command -v dpkg-deb >/dev/null 2>&1 || die "dpkg-deb is required to inspect the downloaded package."

  local architecture temp_dir deb_file package_name package_architecture
  architecture="$(dpkg --print-architecture)"
  [[ "$architecture" == "amd64" ]] || die "The published Grok Bot Linux beta supports amd64; detected $architecture."

  log "Installing Grok Bot download prerequisites"
  run_root apt-get update
  run_root apt-get install -y ca-certificates curl

  temp_dir="$(mktemp -d)"
  trap "rm -rf '$temp_dir'" EXIT
  deb_file="$temp_dir/grok-bot_amd64.deb"

  log "Downloading official Grok Bot Linux beta"
  curl -fL --retry 3 -o "$deb_file" "$GROK_BOT_DOWNLOAD_URL"
  [[ -s "$deb_file" ]] || die "Downloaded Grok Bot package is empty"

  package_name="$(dpkg-deb -f "$deb_file" Package)"
  package_architecture="$(dpkg-deb -f "$deb_file" Architecture)"
  [[ "$package_name" == "grok-bot" ]] || die "Unexpected package name in Grok Bot download: $package_name"
  [[ "$package_architecture" == "amd64" ]] || die "Unexpected package architecture: $package_architecture"

  log "Installing Grok Bot"
  run_root apt-get install -y "$deb_file"
  dpkg-query -W -f='Grok Bot ${Version} installed\n' grok-bot
  rm -rf "$temp_dir"
  trap - EXIT
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
  if [[ "$INSTALL_CHATGPT" == true ]]; then
    BROWSER="$(find_browser || true)"
    if [[ -z "$BROWSER" && "$DRY_RUN" == true ]]; then
      BROWSER="/path/to/google-chrome-or-chromium"
    fi
    [[ -n "$BROWSER" ]] || die "Install Google Chrome or Chromium first (install-chrome-stylus-catppuccin.sh can install Chrome)."
  fi

  [[ "$INSTALL_CLAUDE" == true ]] && install_claude_desktop
  [[ "$INSTALL_CHATGPT" == true ]] && create_launcher "chatgpt" "ChatGPT" "https://chatgpt.com/" "web-browser"
  [[ "$INSTALL_GROK" == true ]] && install_grok_bot

  if [[ "$DRY_RUN" == false ]] && command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$HOME/.local/share/applications" || true
  fi
  log "AI desktop installation complete"
}

main
