#!/usr/bin/env bash
set -euo pipefail

# Install or update GitHub CLI from GitHub's official Debian/Ubuntu repository.
# Official instructions: https://github.com/cli/cli/blob/trunk/docs/install_linux.md

KEY_URL="https://cli.github.com/packages/githubcli-archive-keyring.gpg"
KEYRING="/etc/apt/keyrings/githubcli-archive-keyring.gpg"
SOURCE_LIST="/etc/apt/sources.list.d/github-cli.list"
REPOSITORY_URL="https://cli.github.com/packages"

log() { printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0")

Installs or updates GitHub CLI (gh) using GitHub's official apt repository.
Run as a normal user; the script requests sudo only for system package changes.
EOF
}

case "${1:-}" in
  "") ;;
  -h|--help) usage; exit 0 ;;
  *) die "Unknown option: $1" ;;
esac

run_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die "sudo is required when this script is not run as root"
  fi
}

main() {
  command -v apt-get >/dev/null 2>&1 || die "This installer requires Debian, Ubuntu, or another apt-based distribution."
  command -v dpkg >/dev/null 2>&1 || die "dpkg is required to determine the package architecture."

  log "Installing repository prerequisites"
  run_root apt-get update
  run_root apt-get install -y ca-certificates wget

  local temp_dir key_file architecture source_line
  temp_dir="$(mktemp -d)"
  trap "rm -rf '$temp_dir'" EXIT
  key_file="$temp_dir/githubcli-archive-keyring.gpg"

  log "Downloading GitHub CLI repository key"
  wget -nv -O "$key_file" "$KEY_URL"
  [[ -s "$key_file" ]] || die "Downloaded GitHub CLI keyring is empty"

  run_root install -d -m 0755 /etc/apt/keyrings /etc/apt/sources.list.d
  run_root install -m 0644 "$key_file" "$KEYRING"

  architecture="$(dpkg --print-architecture)"
  source_line="deb [arch=$architecture signed-by=$KEYRING] $REPOSITORY_URL stable main"
  printf '%s\n' "$source_line" | run_root tee "$SOURCE_LIST" >/dev/null

  log "Installing GitHub CLI"
  run_root apt-get update
  run_root apt-get install -y gh

  command -v gh >/dev/null 2>&1 || die "gh was installed but is not on PATH"
  gh --version

  log "GitHub CLI installation complete"
  printf '%s\n' "Next: run 'gh auth login' to connect your GitHub account."
}

main
