#!/usr/bin/env bash
set -euo pipefail

# Install supported AI coding CLIs for the current user.
# Sources:
#   Claude Code: https://docs.anthropic.com/en/docs/claude-code/getting-started
#   Codex:       https://developers.openai.com/codex/cli
#   Grok Build:  https://docs.x.ai/build/overview

INSTALL_CLAUDE=true
INSTALL_CODEX=true
INSTALL_GROK=true
DRY_RUN=false

log() { printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --only <tool>  Install only claude, codex, or grok (repeatable)
  --no-claude    Skip Claude Code
  --no-codex     Skip Codex CLI
  --no-grok      Skip Grok Build
  --dry-run      Print the install commands without running them
  -h, --help     Show this help

Node.js and npm must already be available for Claude Code and Codex.
Run ./install-node-latest.sh --lts first when needed.
EOF
}

ONLY_SET=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only)
      [[ $# -ge 2 ]] || die "--only requires claude, codex, or grok"
      if [[ "$ONLY_SET" == false ]]; then
        INSTALL_CLAUDE=false; INSTALL_CODEX=false; INSTALL_GROK=false; ONLY_SET=true
      fi
      case "$2" in
        claude) INSTALL_CLAUDE=true ;;
        codex) INSTALL_CODEX=true ;;
        grok) INSTALL_GROK=true ;;
        *) die "Unknown tool for --only: $2" ;;
      esac
      shift 2
      ;;
    --no-claude) INSTALL_CLAUDE=false; shift ;;
    --no-codex) INSTALL_CODEX=false; shift ;;
    --no-grok) INSTALL_GROK=false; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

run() {
  if [[ "$DRY_RUN" == true ]]; then
    printf 'DRY RUN:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

install_npm_cli() {
  local name="$1" package="$2"
  command -v npm >/dev/null 2>&1 || die "npm is required for $name. Run install-node-latest.sh --lts first."
  log "Installing/updating $name"
  run npm install --global "$package"
}

verify() {
  local command_name="$1"
  [[ "$DRY_RUN" == true ]] && return
  command -v "$command_name" >/dev/null 2>&1 || die "$command_name was installed but is not on PATH"
  "$command_name" --version
}

main() {
  [[ "${EUID:-$(id -u)}" -ne 0 ]] || die "Run this script as your normal user, not with sudo."

  if [[ "$INSTALL_CLAUDE" == true ]]; then
    install_npm_cli "Claude Code" "@anthropic-ai/claude-code@latest"
    verify claude
  fi

  if [[ "$INSTALL_CODEX" == true ]]; then
    install_npm_cli "Codex CLI" "@openai/codex@latest"
    verify codex
  fi

  if [[ "$INSTALL_GROK" == true ]]; then
    command -v curl >/dev/null 2>&1 || die "curl is required for Grok Build"
    log "Installing/updating Grok Build"
    if [[ "$DRY_RUN" == true ]]; then
      printf '%s\n' "DRY RUN: curl -fsSL https://x.ai/cli/install.sh | bash"
    else
      # xAI's supported bootstrap installer manages the user-local binary.
      curl -fsSL https://x.ai/cli/install.sh | bash
      export PATH="$HOME/.local/bin:$HOME/.grok/bin:$PATH"
      command -v grok >/dev/null 2>&1 || die "grok was installed but is not on PATH"
      grok version
    fi
  fi

  log "AI CLI installation complete"
  printf '%s\n' "Authenticate on first launch: claude, codex, or grok login."
}

main
