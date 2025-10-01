# Changelog

## v0.2.1

No user-visible or API changes. All updates are internal/maintenance to make builds more robust.

### Build system

- Unified script now handles vendor extraction and triplet guarding.
- Triplet change auto-purges `_build/**/obj` to avoid cross-contamination.
- Inject repo-local `config.sub`/`config.guess` into vendor trees.
- Replace `mecab/Makefile.in` stub with a tiny `configure` patch (fixes `config.status` with external MeCab).
- Streamlined installers:
  - Dictionary: extract to `priv/dictionary` (unwrap `open_jtalk_dic_*` if present).
  - Voice: stream `mei_normal.htsvoice` directly from the zip.
- Centralized RPATH: `$ORIGIN/../lib` (Linux), `@loader_path/../lib` (macOS).

## v0.2.0

### Highlights

- **Simpler build**: consolidated native build into one script; removed configure “stamp”.
- **Assets bundled by default**: dictionary + Mei voice now bundled into `priv/` unless opted out.
- **Wider platform support**: host builds verified on Linux x86_64, Linux aarch64, and macOS 14 (arm64).
- **Cross-compile**: tested `MIX_TARGET=rpi4` (aarch64/Nerves).
- **Better triplet detection**: inject modern `config.sub/config.guess` to fix errors like
  `arm64-apple-darwin… not recognized`.

### Breaking / Migration

- Env vars renamed:
  - `FULL_STATIC` → `OPENJTALK_FULL_STATIC`
  - `BUNDLE_ASSETS` → `OPENJTALK_BUNDLE_ASSETS`
- If you previously relied on assets **not** being bundled, set `OPENJTALK_BUNDLE_ASSETS=0`.

## v0.1.0

Initial release
