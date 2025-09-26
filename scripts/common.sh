#!/usr/bin/env bash
#
# Shared helpers
#
set -euo pipefail

log() { printf '%s\n' "[$(basename "$0")] $*" >&2; }

die() {
  log "ERROR: $*"
  exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

ensure_tools() {
  local missing=()
  for t in "$@"; do have "$t" || missing+=("$t"); done
  ((${#missing[@]} == 0)) || die "Missing tools: ${missing[*]}"
}

# Inject a modern config.sub (+config.guess if available) into a source tree.
copy_config_sub_if_present() {
  local src="${1:-}" dst="${2:-}"
  [[ -n "$src" && -f "$src" && -n "$dst" && -d "$dst" ]] || return 0

  log "Copying $(basename "$src") into $dst (and config/)"
  cp -f "$src" "$dst/config.sub" || true
  mkdir -p "$dst/config"
  cp -f "$src" "$dst/config/config.sub" || true

  local guess
  guess="$(dirname "$src")/config.guess"
  if [[ -f "$guess" ]]; then
    cp -f "$guess" "$dst/config.guess" || true
    cp -f "$guess" "$dst/config/config.guess" || true
  fi
}

# Best-effort cleanup of common Autotools outputs.
clean_autotools_artifacts() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  if [[ -f "$dir/Makefile" ]]; then
    make -C "$dir" distclean || make -C "$dir" clean || true
  fi
  find "$dir" -type f \( -name '*.o' -o -name '*.lo' -o -name '*.la' \) -delete || true
}
