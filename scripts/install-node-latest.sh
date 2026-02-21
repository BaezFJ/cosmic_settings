#!/usr/bin/env bash
set -euo pipefail

# Installs "latest" Node.js via nvm (user-local), configures bashrc, and sets a default version.
# Default: installs latest "Current" (nvm alias "node"). Use --lts to install latest LTS.

MODE="current"        # current | lts
UPDATE_NPM=false      # optionally update npm to latest
INSTALL_DEPS=true     # install apt deps if available

MARKER_BEGIN="# >>> nvm/node setup >>>"
MARKER_END="# <<< nvm/node setup <<<"

log() { printf "\n[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }
die() { printf "\nERROR: %s\n" "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --current       Install latest Node "Current" (default)
  --lts           Install latest Node LTS
  --update-npm    After install, run: npm install -g npm@latest
  --no-deps       Do not install OS dependencies (apt)
  -h, --help      Show help

Notes:
  - Installs nvm under your user (not system-wide).
  - If run with sudo, it targets the original user (\$SUDO_USER).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --current) MODE="current"; shift ;;
    --lts) MODE="lts"; shift ;;
    --update-npm) UPDATE_NPM=true; shift ;;
    --no-deps) INSTALL_DEPS=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

# If run with sudo, target the original user (avoid root-owned files in home).
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
[[ -n "${TARGET_HOME:-}" ]] || TARGET_HOME="$HOME"
BASHRC="${TARGET_HOME}/.bashrc"

run_as_target() {
  # Run a login shell as TARGET_USER
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
  if [[ "$INSTALL_DEPS" != "true" ]]; then
    log "Skipping OS dependency install (--no-deps)."
    return
  fi

  if command -v apt-get >/dev/null 2>&1; then
    log "Installing deps via apt (curl, ca-certificates, git, xz-utils, build-essential, python3)..."
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
      apt-get update -y
      apt-get install -y curl ca-certificates git xz-utils build-essential python3
    elif command -v sudo >/dev/null 2>&1; then
      sudo apt-get update -y
      sudo apt-get install -y curl ca-certificates git xz-utils build-essential python3
    else
      log "No sudo available; skipping apt dependency install."
    fi
  else
    log "apt-get not found; skipping dependency install."
  fi
}

detect_nvm_dir() {
  # Prefer existing installs
  local home="$1"
  if run_as_target "[[ -d \"$home/.nvm\" ]]"; then
    echo "$home/.nvm"
  elif run_as_target "[[ -d \"$home/.config/nvm\" ]]"; then
    echo "$home/.config/nvm"
  else
    echo "$home/.nvm"
  fi
}

get_latest_nvm_tag() {
  # Use GitHub API if possible; fallback to a known recent tag if API fails.
  # (We avoid jq dependency.)
  local tag
  tag="$(curl -fsSL https://api.github.com/repos/nvm-sh/nvm/releases/latest \
    | grep -m1 '"tag_name"' \
    | sed -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/' || true)"
  if [[ -n "${tag:-}" ]]; then
    echo "$tag"
  else
    echo "v0.40.4"
  fi
}

ensure_bashrc_block() {
  run_as_target "mkdir -p \"$(dirname "$BASHRC")\"; touch \"$BASHRC\""

  if run_as_target "grep -qF \"$MARKER_BEGIN\" \"$BASHRC\""; then
    log "nvm block already present in $BASHRC (skipping)."
    return
  fi

  log "Adding nvm sourcing + bash completion to $BASHRC ..."
  run_as_target "cat >> \"$BASHRC\" <<'EOF'

$MARKER_BEGIN
export NVM_DIR=\"\$HOME/.nvm\"
[ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\"  # This loads nvm
[ -s \"\$NVM_DIR/bash_completion\" ] && \\. \"\$NVM_DIR/bash_completion\"  # This loads nvm bash_completion
$MARKER_END
EOF"
}

install_or_update_nvm() {
  need_cmd curl

  local tag
  tag="$(get_latest_nvm_tag)"
  log "Installing/updating nvm ($tag) for user: $TARGET_USER"

  # Tell installer NOT to edit shell config; we manage .bashrc ourselves.
  run_as_target "
    export NVM_DIR=\"$NVM_DIR\"
    export PROFILE=/dev/null
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${tag}/install.sh | bash
  "
}

install_node() {
  log "Installing Node.js via nvm ($MODE) ..."

  if [[ "$MODE" == "lts" ]]; then
    run_as_target "
      export NVM_DIR=\"$NVM_DIR\"
      [ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\"
      nvm install --lts
      nvm alias default lts/*
      nvm use default
      node -v
      npm -v
    "
  else
    run_as_target "
      export NVM_DIR=\"$NVM_DIR\"
      [ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\"
      nvm install node
      nvm alias default node
      nvm use default
      node -v
      npm -v
    "
  fi

  if [[ "$UPDATE_NPM" == "true" ]]; then
    log "Updating npm to latest..."
    run_as_target "
      export NVM_DIR=\"$NVM_DIR\"
      [ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\"
      npm install -g npm@latest
      npm -v
    "
  fi
}

main() {
  log "Target user: $TARGET_USER"
  log "Target home: $TARGET_HOME"

  install_deps

  NVM_DIR="$(detect_nvm_dir "$TARGET_HOME")"
  log "Using NVM_DIR: $NVM_DIR"

  install_or_update_nvm
  ensure_bashrc_block
  install_node

  log "Done."
  echo
  echo "Next:"
  echo "  Restart your terminal, OR run:  source \"$BASHRC\""
  echo
  echo "Tip:"
  echo "  nvm ls"
  echo "  nvm use --lts   # or: nvm use node"
}

main "$@"
