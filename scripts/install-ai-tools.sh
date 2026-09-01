#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
  "") ;;
  --dry-run)
    [[ $# -eq 1 ]] || { printf 'Usage: %s [--dry-run]\n' "$(basename "$0")" >&2; exit 1; }
    ;;
  -h|--help)
    printf 'Usage: %s [--dry-run]\n' "$(basename "$0")"
    printf '%s\n' 'Install every CLI and desktop launcher. Use the component scripts to select a subset.'
    exit 0
    ;;
  *)
    printf 'Usage: %s [--dry-run]\n' "$(basename "$0")" >&2
    printf '%s\n' 'Use the component scripts to select a subset.' >&2
    exit 1
    ;;
esac

"$SCRIPT_DIR/install-ai-clis.sh" "$@"
"$SCRIPT_DIR/install-ai-desktop-apps.sh" "$@"
