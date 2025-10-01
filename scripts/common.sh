#!/usr/bin/env bash
#
# Common helpers
#
set -euo pipefail

# Log to stderr with the script's basename as a prefix.
log() { printf '%s\n' "[$(basename "$0")] $*" >&2; }

# Fail fast with a consistent error line.
die() {
  log "ERROR: $*"
  exit 1
}

# True if a program exists on PATH.
have() { command -v "$1" >/dev/null 2>&1; }

# Ensure a set of tools exist. If any are missing, exit with a helpful message.
ensure_tools() {
  local missing=()
  for t in "$@"; do have "$t" || missing+=("$t"); done
  ((${#missing[@]} == 0)) || die "Missing tools: ${missing[*]}"
}

# Fetch a URL to a destination path (idempotent unless FORCE=1).
# Usage: fetch <url> <dest_path> [chmod+x? (true|false)]
fetch() {
  local url="$1" dest="$2" make_x="${3:-false}"
  if [[ -f "$dest" && "${FORCE:-0}" != "1" ]]; then
    log "exists: $dest"
    return 0
  fi
  log "downloading: $url -> $dest"
  mkdir -p "$(dirname "$dest")"
  # Follow redirects (SF “/download”), fail on HTTP errors, retry a bit for flakiness
  curl -fL --retry 3 --retry-delay 2 -o "$dest" "$url"
  if [[ "$make_x" == "true" ]]; then chmod +x "$dest" || true; fi
}
