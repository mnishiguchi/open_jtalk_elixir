#!/usr/bin/env bash
#
# Prepare vendor/ with pinned source + asset archives and gnuconfig scripts.
# Usage:
#   scripts/prepare_vendor.sh         # download anything missing
#   scripts/prepare_vendor.sh --force # re-download everything
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

main() {
  # Force toggle
  if [[ "${1:-}" == "--force" ]]; then FORCE=1; else FORCE=0; fi

  ensure_tools curl mkdir

  # Repo root = script's parent dir
  ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
  VENDOR_DIR="$ROOT_DIR/vendor"

  # Layout we’re ensuring:
  # vendor/
  # ├── config/{config.guess,config.sub}
  # ├── hts_engine_API-1.10.tar.gz
  # ├── mecab-0.996.tar.gz
  # ├── MMDAgent_Example-1.8.zip
  # ├── open_jtalk-1.11.tar.gz
  # └── open_jtalk_dic_utf_8-1.11.tar.gz
  mkdir -p "$VENDOR_DIR/config"

  # 1) gnuconfig
  fetch "https://gitweb.git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD" \
    "$VENDOR_DIR/config/config.sub" true
  fetch "https://gitweb.git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD" \
    "$VENDOR_DIR/config/config.guess" true

  # 2) sources
  fetch "https://sourceforge.net/projects/open-jtalk/files/Open%20JTalk/open_jtalk-1.11/open_jtalk-1.11.tar.gz/download" \
    "$VENDOR_DIR/open_jtalk-1.11.tar.gz"
  fetch "https://sourceforge.net/projects/hts-engine/files/hts_engine%20API/hts_engine_API-1.10/hts_engine_API-1.10.tar.gz/download" \
    "$VENDOR_DIR/hts_engine_API-1.10.tar.gz"
  fetch "https://deb.debian.org/debian/pool/main/m/mecab/mecab_0.996.orig.tar.gz" \
    "$VENDOR_DIR/mecab-0.996.tar.gz"

  # 3) assets
  fetch "https://sourceforge.net/projects/open-jtalk/files/Dictionary/open_jtalk_dic-1.11/open_jtalk_dic_utf_8-1.11.tar.gz/download" \
    "$VENDOR_DIR/open_jtalk_dic_utf_8-1.11.tar.gz"
  fetch "https://sourceforge.net/projects/mmdagent/files/MMDAgent_Example/MMDAgent_Example-1.8/MMDAgent_Example-1.8.zip/download" \
    "$VENDOR_DIR/MMDAgent_Example-1.8.zip"

  log "done. vendor prepared at: $VENDOR_DIR"
}

main "$@"
