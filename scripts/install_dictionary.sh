#!/usr/bin/env bash
#
# Install the UTF-8 dictionary tarball into DEST_DIR.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

ensure_tools tar

: "${DIC_TGZ:?set DIC_TGZ}"
: "${DEST_DIR:?set DEST_DIR}"

# Fresh install dir
rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR"

# Extract directly into DEST_DIR.
tar -xzf "$DIC_TGZ" -C "$DEST_DIR"

# Some tarballs wrap contents in open_jtalk_dic_*/; if so, move them up one level.
# Gotcha: Use dotglob to move hidden files too.
if [[ ! -f "$DEST_DIR/sys.dic" ]]; then
  for d in "$DEST_DIR"/open_jtalk* "$DEST_DIR"/open-jtalk*; do
    if [[ -d "$d" ]]; then
      shopt -s dotglob nullglob
      mv "$d"/* "$DEST_DIR"/
      rmdir "$d" || true
      shopt -u dotglob nullglob
      break
    fi
  done
fi

[[ -f "$DEST_DIR/sys.dic" ]] || die "sys.dic not found after extracting $DIC_TGZ"
