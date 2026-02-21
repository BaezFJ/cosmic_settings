#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.google.Chrome"
FLATHUB_REMOTE="flathub"
FLATHUB_REPO_URL="https://flathub.org/repo/flathub.flatpakrepo"

# Stylus (Chrome Web Store) extension ID
STYLUS_ID="clngdbkpkpeebahjckkjfobafhncgmne"
# Chrome Web Store update endpoint (official)
CWS_UPDATE_URL="https://clients2.google.com/service/update2/crx"

# Catppuccin "All Userstyles" compiled Stylus export (recommended)
CATPPUCCIN_IMPORT_URL="https://github.com/catppuccin/userstyles/releases/download/all-userstyles-export/import.json"

# Where we place the external extension JSON (official Linux locations include /usr/share/google-chrome/extensions)
EXT_DIR="/usr/share/google-chrome/extensions"
EXT_JSON="${EXT_DIR}/${STYLUS_ID}.json"

# Flatpak Chrome doesn't read host /usr/share by default; mount JUST this directory read-only.
FLATPAK_OVERRIDE_FS="${EXT_DIR}:ro"

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
[[ -n "${TARGET_HOME:-}" ]] || TARGET_HOME="$HOME"
DOWNLOADS_DIR="${TARGET_HOME}/Downloads"
CATPPUCCIN_FILE="${DOWNLOADS_DIR}/catppuccin-stylus-import.json"

log() { printf "\n[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }
warn() { printf "\n[%s] WARNING: %s\n" "$(date +%H:%M:%S)" "$*" >&2; }
die() { printf "\nERROR: %s\n" "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing '$1'. Install it and re-run."; }

install_deps() {
  if command -v apt-get >/dev/null 2>&1; then
    log "Installing dependencies via apt (flatpak, curl)..."
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
      apt-get update -y
      apt-get install -y flatpak curl
    elif command -v sudo >/dev/null 2>&1; then
      sudo apt-get update -y
      sudo apt-get install -y flatpak curl
    else
      warn "No sudo available; skipping apt deps."
    fi
  fi
}

ensure_flathub() {
  if ! flatpak remotes | awk '{print $1}' | grep -qx "$FLATHUB_REMOTE"; then
    log "Adding Flathub remote..."
    flatpak remote-add --if-not-exists "$FLATHUB_REMOTE" "$FLATHUB_REPO_URL"
  else
    log "Flathub remote already present."
  fi
}

install_chrome_flatpak() {
  log "Installing Google Chrome (Flatpak) $APP_ID ..."
  flatpak install -y "$FLATHUB_REMOTE" "$APP_ID"
}

setup_flatpak_override() {
  log "Applying Flatpak override so Chrome can read: $FLATPAK_OVERRIDE_FS"
  flatpak override --user --filesystem="$FLATPAK_OVERRIDE_FS" "$APP_ID"
}

install_stylus_external_extension() {
  # Official Linux external extension method: create <id>.json with external_update_url (auto-installs)
  # Needs root to write to /usr/share.
  log "Attempting to install Stylus as an external extension (requires sudo/root)..."

  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    mkdir -p "$EXT_DIR"
    cat > "$EXT_JSON" <<EOF
{
  "external_update_url": "${CWS_UPDATE_URL}"
}
EOF
    chmod 0644 "$EXT_JSON"
    log "Wrote: $EXT_JSON"
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo mkdir -p "$EXT_DIR"
    sudo tee "$EXT_JSON" >/dev/null <<EOF
{
  "external_update_url": "${CWS_UPDATE_URL}"
}
EOF
    sudo chmod 0644 "$EXT_JSON"
    log "Wrote: $EXT_JSON"
    return 0
  fi

  warn "Could not write $EXT_JSON (no root/sudo). Stylus will need manual install from the Chrome Web Store."
  return 1
}

download_catppuccin_import() {
  log "Downloading Catppuccin Stylus export to: $CATPPUCCIN_FILE"
  mkdir -p "$DOWNLOADS_DIR"
  curl -LfsS "$CATPPUCCIN_IMPORT_URL" -o "$CATPPUCCIN_FILE"
}

launch_chrome_setup_tabs() {
  log "Launching Chrome with setup tabs..."

  # Pages to help user finish setup:
  STYLUS_WEBSTORE_URL="https://chromewebstore.google.com/detail/stylus/${STYLUS_ID}"
  CATPPUCCIN_USAGE_URL="https://userstyles.catppuccin.com/getting-started/usage/"
  CHROME_EXT_SETTINGS_URL="chrome://extensions/?id=${STYLUS_ID}"
  # Stylus manage page (works after extension is installed)
  STYLUS_MANAGE_URL="chrome-extension://${STYLUS_ID}/manage.html"

  # Open multiple URLs in one run
  flatpak run "$APP_ID" \
    "$CATPPUCCIN_USAGE_URL" \
    "$STYLUS_WEBSTORE_URL" \
    "$CHROME_EXT_SETTINGS_URL" \
    "$STYLUS_MANAGE_URL" \
    >/dev/null 2>&1 & disown || true
}

print_next_steps() {
  cat <<EOF

✅ Done.

Next steps in Chrome (Catppuccin recommends this flow):
1) Ensure Stylus is installed.
   - If you ran with sudo, it should auto-install on Chrome start.
   - If not, install it from the opened Chrome Web Store tab.

2) Enable file URL support for Stylus:
   - Open: chrome://extensions/?id=${STYLUS_ID}
   - Toggle: “Allow access to file URLs”

3) Import Catppuccin styles into Stylus:
   - Open Stylus “Manage” page (tab should already be open)
   - Sidebar → Backup → Import
   - Select: ${CATPPUCCIN_FILE}

EOF
}

main() {
  install_deps
  need_cmd flatpak
  need_cmd curl

  ensure_flathub
  install_chrome_flatpak

  # Allow Chrome Flatpak to read the external extension dir
  setup_flatpak_override

  # Try to install Stylus automatically (best effort)
  install_stylus_external_extension || true

  # Download Catppuccin import file
  download_catppuccin_import

  # Open helpful tabs
  launch_chrome_setup_tabs

  print_next_steps
}

main "$@"
