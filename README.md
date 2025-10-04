# open_jtalk_elixir

[![Hex version](https://img.shields.io/hexpm/v/open_jtalk_elixir.svg "Hex version")](https://hex.pm/packages/open_jtalk_elixir)
[![CI](https://github.com/mnishiguchi/open_jtalk_elixir/actions/workflows/ci.yml/badge.svg)](https://github.com/mnishiguchi/open_jtalk_elixir/actions/workflows/ci.yml)

<!-- MODULEDOC -->

Use Open JTalk from Elixir. This package builds a local `open_jtalk` CLI and,
by default, bundles a UTF-8 dictionary and an HTS voice (you can disable this),
exposing convenient functions:

- `OpenJTalk.say/2` — synthesize and play via a system audio player
- `OpenJTalk.to_wav_file/2` — synthesize text to a WAV file
- `OpenJTalk.to_wav_binary/2` — synthesize and return WAV bytes
- `OpenJTalk.Wav.concat_binaries/1` — merge multiple WAV binaries (same format)
- `OpenJTalk.Wav.concat_files/1` — merge multiple WAV files from paths (same format)

## Install

Add the dependency to your `mix.exs`:

```elixir
def deps do
  [
    {:open_jtalk_elixir, "~> 0.2"}
  ]
end
```

Then:

```bash
mix deps.get
mix compile
```

On first compile the project may download and build MeCab, HTS Engine API,
and Open JTalk. By default it also downloads and bundles a UTF-8 dictionary
and a Mei voice into `priv/` (you can turn this off with
`OPENJTALK_BUNDLE_ASSETS=0`).

### Build requirements

You’ll need common build tools: `gcc`/`g++`, `make`, `curl`, `tar`, `unzip`.
On macOS Xcode Command Line Tools are sufficient.

Optional environment flags (honored by the Makefile):

- `OPENJTALK_FULL_STATIC=1` — attempt a fully static `open_jtalk` (Linux only; requires static libstdc++)
- `OPENJTALK_BUNDLE_ASSETS=0|1` — whether to bundle dictionary/voice into `priv/`

### Tested platforms

Host builds (compile and run on the same machine):

- Linux x86_64
- Linux aarch64
- macOS 14 (arm64, Apple Silicon)

Cross-compile (host → target):

- Linux x86_64 → Nerves rpi4 (aarch64)

## Quick start

```elixir
# play via system audio player (aplay/paplay/afplay/play)
OpenJTalk.say("元氣ですかあ 、元氣が有れば、なんでもできる")
```

### Options

All synthesis calls accept the same options (values are clamped):

- `:timbre` — voice color offset `-0.8..0.8` (default `0.0`)
- `:pitch_shift` — semitones `-24..24` (default `0`)
- `:rate` — speaking speed `0.5..2.0` (default `1.0`)
- `:gain` — output gain in dB (default `0`)
- `:voice` — path to a `.htsvoice` file (optional)
- `:dictionary` — path to a directory containing `sys.dic` (optional)
- `:timeout` — max runtime in ms (default `20_000`)
- `:out` — output WAV path (only for `to_wav_file/2`)

### Concatenate WAVs

You can combine multiple WAVs (same format: channels/rate/bit depth/etc.) into one:

```elixir
{:ok, a} = OpenJTalk.to_wav_binary("これは一つ目。")
{:ok, b} = OpenJTalk.to_wav_binary("これは二つ目。")
{:ok, c} = OpenJTalk.to_wav_binary("これは三つ目。")

{:ok, merged} = OpenJTalk.Wav.concat_binaries([a, b, c])
# or from files:
# {:ok, merged} = OpenJTalk.Wav.concat_files(["a.wav", "b.wav", "c.wav"])
```

<!-- MODULEDOC -->

## How asset resolution works

The package resolves required assets in this order:

1. Environment variable override
2. Bundled asset in `priv/`
3. System-installed location

### CLI binary (`open_jtalk`)

- **Env:** `OPENJTALK_CLI` — full path to `open_jtalk`.
- **Bundled:** `priv/bin/open_jtalk` (built during compile).
- **System:** `open_jtalk` found on `$PATH`.

### Dictionary (`sys.dic`)

- **Env:** `OPENJTALK_DICTIONARY_DIR` — directory containing `sys.dic`.
- **Bundled:** `priv/dictionary/sys.dic` or any `priv/dictionary/**/sys.dic` (e.g. `naist-jdic`).
- **System:** common locations such as `/var/lib/mecab/dic/open-jtalk/naist-jdic`,
  `/usr/lib/*/mecab/dic/open-jtalk/naist-jdic`, etc.

### Voice (`.htsvoice`)

- **Env:** `OPENJTALK_VOICE` — path to a `.htsvoice` file.
- **Bundled:** first file matching `priv/voices/**/*.htsvoice`.
- **System:** standard locations like `/usr/share/hts-voice/**` or `/usr/local/share/hts-voice/**`.

If you change environment variables at runtime (or move files), refresh the
cached paths:

```elixir
OpenJTalk.Assets.reset_cache()
```

## Using with Nerves

This library is Nerves-aware. When `MIX_TARGET` is set the build defaults to:

- `OPENJTALK_FULL_STATIC=1` — try to statically link the CLI on Linux targets when possible
- `OPENJTALK_BUNDLE_ASSETS=1` — bundle CLI, dictionary, and voice into `priv/`

So for many projects no extra configuration is needed.

### Quick Nerves flow

```bash
export MIX_TARGET=rpi4
mix deps.get
mix compile
mix firmware
```

On the device:

```elixir
{:ok, info} = OpenJTalk.info()
# bundled assets should show up as :bundled

OpenJTalk.say("こんにちは")
```

### Audio on Nerves

`OpenJTalk.say/2` requires a system audio player. Most Nerves images use ALSA
`aplay`. If your image does not include a player:

- add one to the system image, or
- use `OpenJTalk.to_wav_file/2` and play the WAV with your chosen mechanism.

### Firmware size notes

Bundling the full dictionary + voice + binary increases firmware size. Approximate
(uncompressed) sizes:

- Dictionary: ~103 MB
- Mei voice: ~2.2 MB
- CLI binary: ~2.4 MB

If that’s too large you can avoid bundling at compile time and provision assets
separately (rootfs overlay, `/data`, OTA, etc.):

```bash
MIX_TARGET=rpi4 OPENJTALK_BUNDLE_ASSETS=0 mix deps.compile open_jtalk_elixir
```

Then point the library to the provisioned assets (for example in
`config/runtime.exs`):

```elixir
System.put_env("OPENJTALK_CLI", "/data/open_jtalk/bin/open_jtalk")
System.put_env("OPENJTALK_DICTIONARY_DIR", "/data/open_jtalk/dic")
System.put_env("OPENJTALK_VOICE", "/data/open_jtalk/voices/mei_normal.htsvoice")

OpenJTalk.Assets.reset_cache()
```

How you provision those files into your image is outside the scope of this
library.

## Third-party components and licenses

This package does not redistribute third-party assets by default.
At compile time it may download and build the following components:

- **Open JTalk 1.11**
  - License: Modified BSD (3-Clause)
  - Source: http://open-jtalk.sourceforge.net/
- **HTS Engine API 1.10**
  - License: Modified BSD (3-Clause)
  - Source: http://hts-engine.sourceforge.net/
- **MeCab 0.996**
  - License: Tri-licensed (GPL / LGPL / BSD); used under BSD terms
  - Source: https://taku910.github.io/mecab/
- **Open JTalk Dictionary (NAIST-JDIC UTF-8) 1.11**
  - License: BSD-style by NAIST
  - Source: https://sourceforge.net/projects/open-jtalk/files/Dictionary/
- **HTS Voice “Mei” (MMDAgent_Example 1.8)**
  - License: CC BY 3.0
  - Source: https://sourceforge.net/projects/mmdagent/files/MMDAgent_Example/
  - Attribution: “HTS Voice ‘Mei’ © Nagoya Institute of Technology, licensed CC BY 3.0.”
