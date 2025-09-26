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

# Inject a modern config.sub (+config.guess if available) into a source tree.
# Why: Autotools shipped with these projects is old; modern triplets
# (e.g. aarch64, *-unknown-* canonicalization) need newer scripts.
# Safe to no-op if the caller didn’t pass CONFIG_SUB or the dst is absent.
copy_config_sub_if_present() {
  local src="${1:-}" dst="${2:-}"
  [[ -n "$src" && -f "$src" && -n "$dst" && -d "$dst" ]] || return 0

  log "Copying $(basename "$src") into $dst (and config/)"
  cp -f "$src" "$dst/config.sub" || true
  mkdir -p "$dst/config"
  cp -f "$src" "$dst/config/config.sub" || true

  # If a sibling config.guess exists, copy it as well; some configure scripts
  # shell out to it for canonicalization.
  local guess
  guess="$(dirname "$src")/config.guess"
  if [[ -f "$guess" ]]; then
    cp -f "$guess" "$dst/config.guess" || true
    cp -f "$guess" "$dst/config/config.guess" || true
  fi
}

# Best-effort cleanup of common Autotools outputs.
# Useful when re-configuring the same source tree for a different host triplet.
clean_autotools_artifacts() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  if [[ -f "$dir/Makefile" ]]; then
    make -C "$dir" distclean || make -C "$dir" clean || true
  fi
  find "$dir" -type f \( -name '*.o' -o -name '*.lo' -o -name '*.la' \) -delete || true
}
