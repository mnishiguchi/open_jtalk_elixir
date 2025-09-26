#!/usr/bin/env bash
#
# Install one HTS voice (Mei) into DEST_VOICE by streaming directly from the zip.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

ensure_tools unzip

: "${VOICE_ZIP:?set VOICE_ZIP}"
: "${DEST_VOICE:?set DEST_VOICE}"

# Find the first entry that ends with mei_normal.htsvoice and stream it out.
# Gotcha: Some zips prefix with different top-level dirs; don't hardcode paths.
entry="$(unzip -Z1 "$VOICE_ZIP" | grep -E '(^|/)mei_normal\.htsvoice$' | head -n1 || true)"
[[ -n "$entry" ]] || die "mei_normal.htsvoice not found in $VOICE_ZIP"

mkdir -p "$(dirname "$DEST_VOICE")"
# Stream the file directly from the zip without unpacking the whole archive.
unzip -p "$VOICE_ZIP" "$entry" >"$DEST_VOICE"
chmod 0644 "$DEST_VOICE"
