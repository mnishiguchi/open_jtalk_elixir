#!/usr/bin/env bash
#
# MeCab + HTS Engine + Open JTalk unified build.
# Some Open JTalk 1.11 tarballs list mecab/Makefile.in in AC_CONFIG_FILES even
# when using an external MeCab. We prune that entry from `configure` so
# `config.status` doesn’t look for a non-existent file.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# Remove any 'mecab/Makefile.in' outputs from Open JTalk's configure to avoid
# config.status errors when building against an external MeCab.
prune_mecab_makefile_in_from_configure() {
  local ojt_dir="$1"
  local cfg="$ojt_dir/configure"
  [[ -f "$cfg" ]] || return 0

  if grep -q "mecab/Makefile\.in" "$cfg"; then
    log "Pruning mecab/Makefile.in from configure"
    sed -i.bak \
      -e 's/[[:space:]]mecab\/Makefile\.in//g' \
      -e "s/[[:space:]]'mecab\/Makefile\.in'//g" \
      -e 's/[[:space:]]"mecab\/Makefile\.in"//g' \
      "$cfg"
  fi
}

build_mecab() {
  local src="$1" prefix="$2" host="$3"
  [[ -d "$src" ]] || die "MeCab source not found: $src"
  if [[ -f "$prefix/lib/libmecab.a" ]]; then
    log "MeCab already present -> $prefix/lib/libmecab.a"
    return 0
  fi
  log "Building MeCab -> $prefix"
  clean_autotools_artifacts "$src"
  copy_config_sub_if_present "${CONFIG_SUB:-}" "$src"
  (
    cd "$src"
    env LC_ALL=C CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" \
      ./configure \
      --prefix="$prefix" \
      --with-charset=utf8 \
      --enable-static --disable-shared \
      --host="$host"
    make
    make install
  )
  [[ -f "$prefix/lib/libmecab.a" ]] || die "libmecab.a missing"
}

build_hts_engine() {
  local src="$1" prefix="$2" host="$3"
  [[ -d "$src" ]] || die "HTS Engine source not found: $src"
  if [[ -f "$prefix/lib/libHTSEngine.a" ]]; then
    log "HTS Engine already present -> $prefix/lib/libHTSEngine.a"
    return 0
  fi
  log "Building HTS Engine -> $prefix"
  clean_autotools_artifacts "$src"
  copy_config_sub_if_present "${CONFIG_SUB:-}" "$src"
  (
    cd "$src"
    env LC_ALL=C CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" \
      ./configure \
      --prefix="$prefix" \
      --enable-static --disable-shared \
      --host="$host"
    make
    make install
  )
  [[ -f "$prefix/lib/libHTSEngine.a" ]] || die "libHTSEngine.a missing"
}

configure_open_jtalk() {
  local ojt_dir="$1" deps_prefix="$2" ojt_prefix="$3" host="$4"
  [[ -d "$ojt_dir" ]] || die "Open JTalk source dir not found: $ojt_dir"

  local mcfg="$deps_prefix/bin/mecab-config"
  [[ -x "$mcfg" ]] || die "mecab-config not found at $mcfg"

  # Some OJT 1.11 tarballs don’t ship mecab/Makefile.in but config.status expects it.
  prune_mecab_makefile_in_from_configure "$ojt_dir"

  log "Configuring Open JTalk (MECAB_CONFIG=$mcfg)"
  copy_config_sub_if_present "${CONFIG_SUB:-}" "$ojt_dir"
  (
    cd "$ojt_dir"
    env LC_ALL=C \
      PATH="$deps_prefix/bin:$PATH" \
      MECAB_CONFIG="$mcfg" \
      CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" \
      CPPFLAGS="$EXTRA_CPPFLAGS" \
      LDFLAGS="$EXTRA_LDFLAGS" \
      ./configure \
      --prefix="$ojt_prefix" \
      --with-hts-engine-header-path="$deps_prefix/include" \
      --with-hts-engine-library-path="$deps_prefix/lib" \
      --host="$host"
  )
  [[ -f "$ojt_dir/config.status" ]] || die "Open JTalk configure failed"
  if [[ -f "$ojt_dir/config.log" ]]; then
    log "configure summary (grep mecab-config):"
    (grep -i "mecab-config" "$ojt_dir/config.log" || true) | sed 's/^/[cfg] /'
  fi
}

find_open_jtalk_bin() {
  local ojt_dir="$1"
  [[ -x "$ojt_dir/src/open_jtalk" ]] && {
    echo "$ojt_dir/src/open_jtalk"
    return
  }
  find "$ojt_dir" -maxdepth 2 -type f -name open_jtalk -perm -u+x | head -n1
}

build_install_open_jtalk() {
  local ojt_dir="$1" deps_prefix="$2" dest_bin="$3"
  log "Building open_jtalk"
  (
    cd "$ojt_dir"
    set +e
    env LC_ALL=C PATH="$deps_prefix/bin:$PATH" MECAB_CONFIG="$deps_prefix/bin/mecab-config" \
      CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" \
      make -C "$ojt_dir/src" open_jtalk 2>/dev/null
    rc=$?
    if [[ $rc -ne 0 ]]; then
      env LC_ALL=C PATH="$deps_prefix/bin:$PATH" MECAB_CONFIG="$deps_prefix/bin/mecab-config" \
        CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" \
        make all
    fi
    set -e
  )
  local src_bin
  src_bin="$(find_open_jtalk_bin "$ojt_dir")"
  [[ -n "${src_bin:-}" && -f "$src_bin" ]] || die "open_jtalk binary not produced"
  mkdir -p "$(dirname "$dest_bin")"
  install -m 0755 "$src_bin" "$dest_bin"
  "$STRIP_BIN" "$dest_bin" || true
  log "Installed: $dest_bin"
}

main() {
  : "${MECAB_SRC:?set MECAB_SRC}"
  : "${HTS_SRC:?set HTS_SRC}"
  : "${OJT_SRC:?set OJT_SRC}"
  : "${OJT_DEPS_PREFIX:?set OJT_DEPS_PREFIX}"
  : "${OJT_PREFIX:?set OJT_PREFIX}"
  : "${HOST:?set HOST}"
  : "${DEST_BIN:?set DEST_BIN}"

  CC="${CC:-gcc}"
  CXX="${CXX:-g++}"
  AR="${AR:-ar}"
  RANLIB="${RANLIB:-ranlib}"
  STRIP_BIN="${STRIP_BIN:-strip}"
  EXTRA_CPPFLAGS="${EXTRA_CPPFLAGS:-}"
  EXTRA_LDFLAGS="${EXTRA_LDFLAGS:-}"
  CONFIG_SUB="${CONFIG_SUB:-}"

  ensure_tools make install find

  log "host=$HOST"
  log "deps=$OJT_DEPS_PREFIX"
  log "dest=$DEST_BIN"

  build_mecab "$MECAB_SRC" "$OJT_DEPS_PREFIX" "$HOST"
  build_hts_engine "$HTS_SRC" "$OJT_DEPS_PREFIX" "$HOST"
  configure_open_jtalk "$OJT_SRC" "$OJT_DEPS_PREFIX" "$OJT_PREFIX" "$HOST"
  build_install_open_jtalk "$OJT_SRC" "$OJT_DEPS_PREFIX" "$DEST_BIN"

  log "Done."
}

main "$@"
