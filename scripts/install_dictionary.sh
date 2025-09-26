#!/usr/bin/env bash
#
# Install UTF-8 dictionary tarball into DEST_DIR (expects sys.dic present).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

ensure_tools tar mktemp find

: "${DIC_TGZ:?set DIC_TGZ}"
: "${DEST_DIR:?set DEST_DIR}"

tmpd="$(mktemp -d)"
trap 'rm -rf "$tmpd"' EXIT

tar -xzf "$DIC_TGZ" -C "$tmpd"
root="$(find "$tmpd" -maxdepth 1 -type d -name 'open_jtalk_dic*' -print -quit || true)"
[[ -n "$root" ]] || root="$tmpd"

rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR"
cp -R "$root"/* "$DEST_DIR/"

test -f "$DEST_DIR/sys.dic" || die "sys.dic not found in $DEST_DIR"
