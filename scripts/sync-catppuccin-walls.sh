#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/orangci/walls-catppuccin-mocha.git"
REPO_NAME="walls-catppuccin-mocha"
BRANCH="master"

# If run with sudo, operate on the original user (so we sync into *their* Pictures folder).
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
[[ -n "${TARGET_HOME:-}" ]] || TARGET_HOME="$HOME"

XDG_CACHE_HOME="${XDG_CACHE_HOME:-$TARGET_HOME/.cache}"
CACHE_DIR="$XDG_CACHE_HOME/$REPO_NAME"

PICTURES_DIR="$TARGET_HOME/Pictures"
# Prefer correct spelling if it already exists; otherwise use the path you requested.
if [[ -d "$PICTURES_DIR/Wallpapers" ]]; then
  WALL_ROOT="$PICTURES_DIR/Wallpapers"
else
  WALL_ROOT="$PICTURES_DIR/Wallpaters"
fi

DEST_DIR="$WALL_ROOT/$REPO_NAME"

log() { printf "\n[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }
die() { printf "\nERROR: %s\n" "$*" >&2; exit 1; }

run_as_target() {
  # Run commands as the target user (avoid root-owned files in their home).
  if [[ "$USER" == "$TARGET_USER" && "${EUID:-$(id -u)}" -ne 0 ]]; then
    bash -lc "$*"
  else
    sudo -u "$TARGET_USER" bash -lc "$*"
  fi
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing '$1'. Install it and re-run."; }

SYNC_DELETE=false
FLAT_COPY=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --delete   Mirror changes by deleting wallpapers removed from the repo (safe: only affects $DEST_DIR)
  --flat     Copy images directly into $WALL_ROOT (no subfolder)
  -h, --help Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --delete) SYNC_DELETE=true; shift ;;
    --flat)   FLAT_COPY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

main() {
  need_cmd rsync

  log "Target user: $TARGET_USER"
  log "Cache dir: $CACHE_DIR"
  log "Wallpaper root: $WALL_ROOT"

  run_as_target "mkdir -p \"$WALL_ROOT\""

  # Clone / update
  if command -v git >/dev/null 2>&1; then
    if run_as_target "[[ -d \"$CACHE_DIR/.git\" ]]"; then
      log "Updating repo in cache..."
      run_as_target "
        git -C \"$CACHE_DIR\" remote set-url origin \"$REPO_URL\"
        git -C \"$CACHE_DIR\" fetch --depth 1 origin \"$BRANCH\"
        git -C \"$CACHE_DIR\" reset --hard \"origin/$BRANCH\"
      "
    else
      log "Cloning repo into cache..."
      run_as_target "mkdir -p \"$(dirname "$CACHE_DIR")\""
      run_as_target "git clone --depth 1 --branch \"$BRANCH\" \"$REPO_URL\" \"$CACHE_DIR\""
    fi
    SRC_DIR="$CACHE_DIR"
  else
    # Fallback: zip download (requires curl + unzip) — uses master branch archive
    need_cmd curl
    need_cmd unzip
    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TMP_DIR"' EXIT

    ZIP_URL="https://github.com/orangci/walls-catppuccin-mocha/archive/refs/heads/${BRANCH}.zip"
    log "git not found; downloading ZIP archive..."
    run_as_target "curl -L \"$ZIP_URL\" -o \"$TMP_DIR/repo.zip\""
    run_as_target "unzip -q \"$TMP_DIR/repo.zip\" -d \"$TMP_DIR\""
    SRC_DIR="$TMP_DIR/${REPO_NAME}-${BRANCH}"
  fi

  if [[ "$FLAT_COPY" == "true" ]]; then
    DEST_DIR="$WALL_ROOT"
    log "Flat copy enabled (no subfolder)."
  else
    run_as_target "mkdir -p \"$DEST_DIR\""
  fi

  log "Syncing images to: $DEST_DIR"

  # Only copy common wallpaper image extensions; ignore README and other files.
  RSYNC_DELETE_FLAG=""
  if [[ "$SYNC_DELETE" == "true" && "$FLAT_COPY" != "true" ]]; then
    RSYNC_DELETE_FLAG="--delete"
  fi

  run_as_target "
    rsync -a $RSYNC_DELETE_FLAG \
      --prune-empty-dirs \
      --include '*/' \
      --include '*.jpg' --include '*.jpeg' --include '*.png' --include '*.webp' --include '*.bmp' --include '*.gif' --include '*.tif' --include '*.tiff' \
      --exclude '*' \
      \"$SRC_DIR/\" \"$DEST_DIR/\"
  "

  log "Done."
  run_as_target "find \"$DEST_DIR\" -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' -o -iname '*.tif' -o -iname '*.tiff' \\) | wc -l | xargs echo \"Wallpapers synced:\""
  echo "Location: $DEST_DIR"
}

main
