#!/usr/bin/env bash
#
# MeCab + HTS Engine + Open JTalk unified build.
#
# Responsibilities:
# - Enforce host-triplet consistency (purge _build/.../obj on change to avoid
#   cross-contamination when switching host/target).
# - Unpack vendor tarballs on demand into _build/.../obj/vendor/*.
# - Canonicalize/patch Autotools bits where upstream is older (config.sub).
# - Work around an Open JTalk 1.11 configure quirk (see below).
#
# Notable gotchas captured here:
# 1) Old config.sub/config.guess in upstream tarballs can’t canonicalize modern
#    triplets (e.g., aarch64, *-nerves-*). We inject our pinned copies.
# 2) Some OJT 1.11 tarballs list `mecab/Makefile.in` in AC_CONFIG_FILES even
#    when using an external MeCab. We prune that token from `configure` so
#    `config.status` doesn’t error out looking for a non-existent file.
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
  for t in "$@"; do
    if ! have "$t"; then
      missing+=("$t")
    fi
  done
  if ((${#missing[@]})); then
    die "Missing tools: ${missing[*]}"
  fi
}

# Inject newer GNU config scripts into given source dir (no-op if not provided).
copy_config_sub_if_present() {
  local src="${1:-}" dst="${2:-}"
  [[ -n "$src" && -f "$src" && -n "$dst" && -d "$dst" ]] || return 0
  log "Injecting $(basename "$src") (+config.guess) into: $dst"
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

# Clean common Autotools outputs so re-configure doesn’t reuse incompatible objects.
clean_autotools_artifacts() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  if [[ -f "$dir/Makefile" ]]; then
    make -C "$dir" distclean || make -C "$dir" clean || true
  fi
  find "$dir" -type f \( -name '*.o' -o -name '*.lo' -o -name '*.la' \) -delete || true
}

# Triplet guard: purge OBJ_DIR if host triplet changed.
ensure_triplet_consistency() {
  local obj_dir="$1" host="$2"
  mkdir -p "$obj_dir"
  local tf="$obj_dir/.host-triplet"
  if [[ -f "$tf" ]]; then
    local prev
    prev="$(cat "$tf" || true)"
    if [[ "$prev" != "$host" ]]; then
      log "Triplet changed ($prev -> $host); purging $obj_dir"
      rm -rf "$obj_dir"
      mkdir -p "$obj_dir"
    fi
  fi
  echo "$host" >"$tf"
}

# Ensure a .tar.gz is extracted to a specific parent/topdir (idempotent).
ensure_extracted() {
  local tgz="$1" parent="$2" topdir="$3"
  [[ -f "$tgz" ]] || die "Archive missing: $tgz"
  local dest="$parent/$topdir"
  if [[ ! -d "$dest" ]]; then
    log "Extracting $(basename "$tgz") -> $parent/"
    mkdir -p "$parent"
    tar -xzf "$tgz" -C "$parent"
  fi
}

# Open JTalk quirk: remove any 'mecab/Makefile.in' outputs to avoid config.status errors
prune_mecab_makefile_in_from_configure() {
  local ojt_dir="$1" cfg="$1/configure"
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

  # Explicitly patch Open JTalk’s configure script to remove any reference to
  # 'mecab/Makefile.in' so that running config.status does not fail when we are
  # intentionally building against an external MeCab (the OJT tarball sometimes
  # lists that file in AC_CONFIG_FILES even though it is not shipped).
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
  : "${OBJ_DIR:?set OBJ_DIR}"
  : "${OBJ_VENDOR:?set OBJ_VENDOR}"
  : "${MECAB_TGZ:?set MECAB_TGZ}"
  : "${HTS_TGZ:?set HTS_TGZ}"
  : "${OJT_TGZ:?set OJT_TGZ}"
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

  ensure_tools make install find tar

  # 0) Triplet guard (may purge OBJ_DIR)
  ensure_triplet_consistency "$OBJ_DIR" "$HOST"

  # 1) Ensure vendor sources are extracted to the fixed directories
  ensure_extracted "$MECAB_TGZ" "$(dirname "$MECAB_SRC")" "$(basename "$MECAB_SRC")"
  ensure_extracted "$HTS_TGZ" "$(dirname "$HTS_SRC")" "$(basename "$HTS_SRC")"
  ensure_extracted "$OJT_TGZ" "$(dirname "$OJT_SRC")" "$(basename "$OJT_SRC")"

  log "host=$HOST"
  log "deps=$OJT_DEPS_PREFIX"
  log "dest=$DEST_BIN"

  # 2) Build
  build_mecab "$MECAB_SRC" "$OJT_DEPS_PREFIX" "$HOST"
  build_hts_engine "$HTS_SRC" "$OJT_DEPS_PREFIX" "$HOST"
  configure_open_jtalk "$OJT_SRC" "$OJT_DEPS_PREFIX" "$OJT_PREFIX" "$HOST"
  build_install_open_jtalk "$OJT_SRC" "$OJT_DEPS_PREFIX" "$DEST_BIN"

  log "Done."
}

main "$@"
