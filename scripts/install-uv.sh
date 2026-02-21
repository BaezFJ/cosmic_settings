#!/usr/bin/env bash
set -euo pipefail

# install-uv.sh
# Installs Astral "uv" and sets up PATH + bash completions.

INSTALL_URL="${INSTALL_URL:-https://astral.sh/uv/install.sh}"
MARKER_BEGIN="# >>> uv setup >>>"
MARKER_END="# <<< uv setup <<<"

log() { printf "\n[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }
die() { printf "\nERROR: %s\n" "$*" >&2; exit 1; }

# If run with sudo, target the original user (so we don't edit root's .bashrc).
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
[[ -n "${TARGET_HOME:-}" ]] || TARGET_HOME="$HOME"

BASHRC="${BASHRC:-$TARGET_HOME/.bashrc}"
UV_INSTALL_DIR="${UV_INSTALL_DIR:-$TARGET_HOME/.local/bin}"

run_as_target() {
  if [[ "$USER" == "$TARGET_USER" && "${EUID:-$(id -u)}" -ne 0 ]]; then
    bash -lc "$*"
  else
    sudo -u "$TARGET_USER" bash -lc "$*"
  fi
}

install_deps() {
  # Minimal deps for Pop!_OS/Ubuntu. Safe to skip if you prefer.
  if command -v apt-get >/dev/null 2>&1; then
    log "Installing dependencies via apt (curl, ca-certificates, python3-venv, git, bash-completion)..."
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
      apt-get update -y
      apt-get install -y curl ca-certificates python3 python3-venv git bash-completion
    elif command -v sudo >/dev/null 2>&1; then
      sudo apt-get update -y
      sudo apt-get install -y curl ca-certificates python3 python3-venv git bash-completion
    else
      log "No sudo found; skipping dependency install."
    fi
  else
    log "apt-get not found; skipping automatic dependency install."
  fi
}

ensure_bashrc_block() {
  run_as_target "mkdir -p \"$(dirname "$BASHRC")\"; touch \"$BASHRC\""

  if run_as_target "grep -qF \"$MARKER_BEGIN\" \"$BASHRC\""; then
    log "uv block already present in $BASHRC (skipping)."
    return
  fi

  log "Adding PATH + completions to $BASHRC ..."
  run_as_target "cat >> \"$BASHRC\" <<'EOF'

$MARKER_BEGIN
# Ensure user-local binaries are available (uv installs here by default).
export PATH=\"\$HOME/.local/bin:\$PATH\"

# Bash completions for uv + uvx
if command -v uv >/dev/null 2>&1; then
  eval \"\$(uv generate-shell-completion bash)\"
fi
if command -v uvx >/dev/null 2>&1; then
  eval \"\$(uvx --generate-shell-completion bash)\"
fi
$MARKER_END
EOF"
}

install_uv() {
  log "Installing uv into: $UV_INSTALL_DIR"
  run_as_target "mkdir -p \"$UV_INSTALL_DIR\""

  # Prevent the installer from modifying shell profiles; we handle .bashrc ourselves.
  # UV_INSTALL_DIR default is ~/.local/bin (we keep it explicit). :contentReference[oaicite:2]{index=2}
  run_as_target "
    command -v curl >/dev/null 2>&1 || exit 10
    curl -LsSf \"$INSTALL_URL\" | env UV_INSTALL_DIR=\"$UV_INSTALL_DIR\" UV_NO_MODIFY_PATH=1 sh
  " || {
    code=$?
    [[ $code -eq 10 ]] && die "curl not found. Install curl first (or let the script install deps via apt)."
    die "uv installer failed with exit code $code"
  }
}

verify() {
  log "Verifying install..."
  run_as_target "export PATH=\"$UV_INSTALL_DIR:\$PATH\"; command -v uv && uv --version"
  run_as_target "export PATH=\"$UV_INSTALL_DIR:\$PATH\"; command -v uvx && uvx --version" || true
}

main() {
  log "Target user: $TARGET_USER"
  log "Target home: $TARGET_HOME"

  install_deps
  install_uv
  ensure_bashrc_block
  verify

  log "Done."
  echo
  echo "Next:"
  echo "  1) Restart your terminal, OR run:  source \"$BASHRC\""
  echo
  echo "Quick start (project workflow):"
  echo "  uv init hello-world && cd hello-world"
  echo "  uv add flask"
  echo "  uv run -- flask run -p 3000"
  echo
}

main "$@"
