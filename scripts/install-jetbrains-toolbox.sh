#!/usr/bin/env bash
set -euo pipefail

# Install JetBrains Toolbox App (latest) for Linux (user-local install).
# Default install dir: ~/.local/opt/jetbrains-toolbox/<version> + symlink "current"
# Adds symlink: ~/.local/bin/jetbrains-toolbox
# Adds desktop entry: ~/.local/share/applications/jetbrains-toolbox.desktop
#
# Options:
#   --autostart   Also create ~/.config/autostart/jetbrains-toolbox.desktop
#   --run         Launch Toolbox after install
#   --no-deps     Skip apt dependency install
#   --clean-old   Remove old versions under ~/.local/opt/jetbrains-toolbox (keeps "current")
#
# Note: If run with sudo, it targets the original user ($SUDO_USER).

AUTOSTART=false
RUN_AFTER=false
INSTALL_DEPS=true
CLEAN_OLD=false

log() { printf "\n[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }
die() { printf "\nERROR: %s\n" "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [--autostart] [--run] [--no-deps] [--clean-old]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --autostart) AUTOSTART=true; shift ;;
    --run) RUN_AFTER=true; shift ;;
    --no-deps) INSTALL_DEPS=false; shift ;;
    --clean-old) CLEAN_OLD=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

# If run with sudo, operate on the original user (avoid root-owned files in home).
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
[[ -n "${TARGET_HOME:-}" ]] || TARGET_HOME="$HOME"

run_as_target() {
  if [[ "$USER" == "$TARGET_USER" && "${EUID:-$(id -u)}" -ne 0 ]]; then
    bash -lc "$*"
  else
    if command -v sudo >/dev/null 2>&1; then
      sudo -u "$TARGET_USER" bash -lc "$*"
    elif command -v runuser >/dev/null 2>&1; then
      runuser -u "$TARGET_USER" -- bash -lc "$*"
    else
      su -s /bin/bash "$TARGET_USER" -c "bash -lc '$*'"
    fi
  fi
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing '$1'. Install it and re-run."; }

install_deps() {
  [[ "$INSTALL_DEPS" == "true" ]] || { log "Skipping deps (--no-deps)."; return; }

  if command -v apt-get >/dev/null 2>&1; then
    log "Installing runtime deps via apt…"
    # JetBrains docs list common libs; libfuse2 is needed for older AppImage-based versions. :contentReference[oaicite:3]{index=3}
    local pkgs=(
      curl ca-certificates tar
      libxi6 libxrender1 libxtst6 mesa-utils fontconfig libgtk-3-bin dbus-user-session
      libfuse2
    )

    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
      apt-get update -y
      apt-get install -y "${pkgs[@]}"
    elif command -v sudo >/dev/null 2>&1; then
      sudo apt-get update -y
      sudo apt-get install -y "${pkgs[@]}"
    else
      log "No sudo available; skipping apt deps."
    fi
  else
    log "apt-get not found; skipping deps."
  fi
}

detect_platform() {
  # JetBrains supports Linux ARM64 builds; map arch to platform string.
  # Common JetBrains platform token for ARM is linuxARM64; x86_64 uses linux.
  local arch
  arch="$(uname -m)"
  case "$arch" in
    aarch64|arm64) echo "linuxARM64" ;;
    x86_64|amd64)  echo "linux" ;;
    *)             echo "linux" ;;
  esac
}

main() {
  log "Target user: $TARGET_USER"
  log "Target home: $TARGET_HOME"

  install_deps
  need_cmd curl
  need_cmd tar

  local platform download_url tmp_dir tarball extracted_dir install_root versioned_dir exe_path
  platform="$(detect_platform)"
  download_url="https://data.services.jetbrains.com/products/download?platform=${platform}&code=TBA"

  install_root="$TARGET_HOME/.local/opt/jetbrains-toolbox"
  run_as_target "mkdir -p \"$install_root\" \"$TARGET_HOME/.local/bin\""

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT

  tarball="$tmp_dir/jetbrains-toolbox.tar.gz"

  log "Downloading latest Toolbox App (${platform})…"
  # This endpoint always points to the latest Toolbox App tarball. :contentReference[oaicite:4]{index=4}
  run_as_target "curl -LfsS \"$download_url\" -o \"$tarball\""

  log "Extracting…"
  run_as_target "tar -xzf \"$tarball\" -C \"$tmp_dir\""

  # Find extracted directory (usually jetbrains-toolbox-*)
  extracted_dir="$(run_as_target "find \"$tmp_dir\" -maxdepth 1 -type d -name 'jetbrains-toolbox*' -print | head -n1")"
  [[ -n "${extracted_dir:-}" ]] || die "Could not locate extracted jetbrains-toolbox directory."

  # Locate executable
  exe_path=""
  if run_as_target "[[ -x \"$extracted_dir/jetbrains-toolbox\" ]]"; then
    exe_path="$extracted_dir/jetbrains-toolbox"
  elif run_as_target "[[ -x \"$extracted_dir/bin/jetbrains-toolbox\" ]]"; then
    exe_path="$extracted_dir/bin/jetbrains-toolbox"
  else
    exe_path="$(run_as_target "find \"$extracted_dir\" -maxdepth 3 -type f -name 'jetbrains-toolbox' -perm -111 -print | head -n1")"
  fi
  [[ -n "${exe_path:-}" ]] || die "Could not find jetbrains-toolbox executable inside archive."

  # Install into ~/.local/opt/jetbrains-toolbox/<foldername>
  versioned_dir="$install_root/$(basename "$extracted_dir")"

  log "Installing to: $versioned_dir"
  # Remove if same version already exists (reinstall)
  run_as_target "rm -rf \"$versioned_dir\""
  run_as_target "mv \"$extracted_dir\" \"$versioned_dir\""

  # Update "current" symlink
  run_as_target "ln -sfn \"$versioned_dir\" \"$install_root/current\""

  # Create a stable symlink in ~/.local/bin
  if run_as_target "[[ -x \"$install_root/current/jetbrains-toolbox\" ]]"; then
    run_as_target "ln -sfn \"$install_root/current/jetbrains-toolbox\" \"$TARGET_HOME/.local/bin/jetbrains-toolbox\""
  else
    run_as_target "ln -sfn \"$install_root/current/bin/jetbrains-toolbox\" \"$TARGET_HOME/.local/bin/jetbrains-toolbox\""
  fi

  # Install an icon (best effort)
  local icon_src icon_dir icon_dst icon_name
  icon_name="jetbrains-toolbox"
  icon_dir="$TARGET_HOME/.local/share/icons/hicolor/256x256/apps"
  run_as_target "mkdir -p \"$icon_dir\""

  icon_src="$(run_as_target "find \"$install_root/current\" -type f \\( -iname '*toolbox*.png' -o -iname '*toolbox*.svg' \\) -print | head -n1" || true)"
  if [[ -n "${icon_src:-}" ]]; then
    icon_dst="$icon_dir/${icon_name}.$(basename "$icon_src" | awk -F. '{print tolower($NF)}')"
    run_as_target "cp -f \"$icon_src\" \"$icon_dst\""
  else
    icon_dst="" # fallback
  fi

  # Create .desktop entry
  local applications_dir desktop_file
  applications_dir="$TARGET_HOME/.local/share/applications"
  desktop_file="$applications_dir/jetbrains-toolbox.desktop"
  run_as_target "mkdir -p \"$applications_dir\""

  log "Creating desktop entry: $desktop_file"
  if [[ -n "${icon_dst:-}" ]]; then
    run_as_target "cat > \"$desktop_file\" <<EOF
[Desktop Entry]
Type=Application
Name=JetBrains Toolbox
Comment=Install, update, and manage JetBrains IDEs
Exec=$TARGET_HOME/.local/bin/jetbrains-toolbox
Icon=$icon_name
Terminal=false
Categories=Development;IDE;
StartupNotify=true
EOF"
  else
    run_as_target "cat > \"$desktop_file\" <<EOF
[Desktop Entry]
Type=Application
Name=JetBrains Toolbox
Comment=Install, update, and manage JetBrains IDEs
Exec=$TARGET_HOME/.local/bin/jetbrains-toolbox
Icon=applications-development
Terminal=false
Categories=Development;IDE;
StartupNotify=true
EOF"
  fi

  # If we installed a real icon, keep the Icon=jetbrains-toolbox name and rely on hicolor
  if [[ -n "${icon_src:-}" ]]; then
    # Ensure correct basename (Icon=jetbrains-toolbox)
    # (GNOME/COSMIC will pick it up from hicolor)
    :
  fi

  # Autostart (optional)
  if [[ "$AUTOSTART" == "true" ]]; then
    local autostart_dir autostart_file
    autostart_dir="$TARGET_HOME/.config/autostart"
    autostart_file="$autostart_dir/jetbrains-toolbox.desktop"
    log "Enabling autostart: $autostart_file"
    run_as_target "mkdir -p \"$autostart_dir\""
    run_as_target "cp -f \"$desktop_file\" \"$autostart_file\""
  fi

  # Clean old versions (optional)
  if [[ "$CLEAN_OLD" == "true" ]]; then
    log "Cleaning old versions in $install_root (keeping 'current')…"
    run_as_target "
      shopt -s nullglob
      for d in \"$install_root\"/jetbrains-toolbox-*; do
        [[ \"\$d\" == \"$(readlink -f "$install_root/current")\" ]] && continue
        rm -rf \"\$d\"
      done
    "
  fi

  # Update desktop database if available (best effort)
  run_as_target "command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database \"$applications_dir\" || true"

  log "Installed!"
  echo "Binary:  $TARGET_HOME/.local/bin/jetbrains-toolbox"
  echo "Menu:    JetBrains Toolbox (desktop entry created)"
  echo "Install: $install_root/current"

  if [[ "$RUN_AFTER" == "true" ]]; then
    log "Launching JetBrains Toolbox…"
    run_as_target "nohup \"$TARGET_HOME/.local/bin/jetbrains-toolbox\" >/dev/null 2>&1 &"
  else
    echo
    echo "To launch now:"
    echo "  $TARGET_HOME/.local/bin/jetbrains-toolbox"
  fi
}

main
