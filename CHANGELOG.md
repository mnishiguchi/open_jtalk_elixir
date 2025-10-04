# Changelog

## v0.3.0

### Breaking changes

- Renamed functions for clarity:
  - `OpenJTalk.to_wav/2` → `OpenJTalk.to_wav_file/2`
  - `OpenJTalk.to_binary/2` → `OpenJTalk.to_wav_binary/2`

### New

- **WAV concatenation**
  - `OpenJTalk.Wav.concat_binaries/1`
  - `OpenJTalk.Wav.concat_files/1`

- **Playback options**
  - `:playback_mode` (`:auto | :stdin | :file`) for `say/2`, `play_wav_binary/2`, and `play_wav_file/2`
  - `OpenJTalk.play_wav_binary/2` — play in-memory WAV bytes directly

### Improvements

- Safer, stricter option validation with `OpenJTalk.validate_options!/1`
- Better error messages for invalid options and timeouts

### Quick upgrade examples

```elixir
{:ok, path} = OpenJTalk.to_wav_file("こんにちは", out: "/tmp/x.wav")
{:ok, wav} = OpenJTalk.to_wav_binary("こんにちは")
:ok = OpenJTalk.say("こんにちは", playback_mode: :auto)
{:ok, merged} = OpenJTalk.Wav.concat_binaries([a, b, c])
```

## v0.2.2

### Highlights

- More robust process execution: `OpenJTalk.Runner` now uses MuonTrap for spawning the `open_jtalk` CLI. This improves timeout handling and process cleanup (useful on Nerves and in supervision trees).

### Changes

- Replace `System.cmd/3` + manual Task/timeout with `MuonTrap.cmd/3` in `OpenJTalk.Runner`.
- Add runtime dependency: `{:muontrap, "~> 1.6"}`.

### Notes

- No API changes. Existing calls (`OpenJTalk.to_wav/2`, `to_binary/2`, `say/2`) are unaffected.
- Builds may compile a tiny native component from MuonTrap (handled automatically).
- Recommended for Nerves users: better handling of timeouts and zombie prevention under constrained environments.

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
