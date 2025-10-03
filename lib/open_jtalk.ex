defmodule OpenJTalk do
  @moduledoc File.read!("README.md")
             |> String.split("<!-- MODULEDOC -->")
             |> Enum.fetch!(1)

  @typedoc "Voice color adjustment. Range: -0.8..0.8 (values are clamped)."
  @type timbre :: float()

  @typedoc "Pitch shift in semitones. Range: -24..24 (values are clamped)."
  @type pitch_shift :: -24..24

  @typedoc "Speaking rate multiplier. Range: 0.5..2.0 (values are clamped)."
  @type rate :: float()

  @typedoc "Output gain in dB. Typical useful range is about -20..20 (values are clamped)."
  @type gain :: number()

  @typedoc """
  Audio playback mode:

    * `:auto`  — prefer stdin when available; otherwise fall back to file playback
    * `:file`  — always use file-based playback
    * `:stdin` — stream WAV bytes via stdin (diskless); falls back to file if unsupported
  """
  @type playback_mode :: :auto | :file | :stdin

  @typedoc "Options accepted by playback functions."
  @type player_option ::
          {:timeout, non_neg_integer()}
          | {:playback_mode, playback_mode()}

  @typedoc "Options accepted by synthesis functions."
  @type synth_option ::
          {:timbre, timbre()}
          | {:pitch_shift, pitch_shift()}
          | {:rate, rate()}
          | {:gain, gain()}
          | {:voice, Path.t()}
          | {:dictionary, Path.t()}
          | {:timeout, non_neg_integer()}

  @typedoc "Options accepted by `say/2` (synth + playback + optional `:out`)."
  @type say_option :: player_option() | synth_option() | {:out, Path.t()}

  @doc """
  Validate options for synthesis and playback.

  Allowed keys:
    * Synthesis: `:timbre`, `:pitch_shift`, `:rate`, `:gain`, `:voice`, `:dictionary`, `:timeout`
    * Playback:  `:playback_mode`, `:timeout`
    * Files:     `:out`

  Enforcement:
    * Unknown keys raise `ArgumentError`
    * `:playback_mode` must be one of `:auto | :file | :stdin` (if present)
    * `:timeout` must be a non-negative integer (if present)

  Returns the original `opts` on success.
  """
  @spec validate_options!(keyword) :: keyword
  def validate_options!(opts) when is_list(opts) do
    check_known_keys!(opts)
    validate_playback_mode!(opts)
    validate_timeout!(opts)
    opts
  end

  defp check_known_keys!(opts) do
    allowed = [
      :timbre,
      :pitch_shift,
      :rate,
      :gain,
      :voice,
      :dictionary,
      :timeout,
      :playback_mode,
      :out
    ]

    unknown =
      opts
      |> Keyword.keys()
      |> Enum.uniq()
      |> Enum.reject(&(&1 in allowed))

    if unknown != [] do
      raise ArgumentError, "unknown option(s) for OpenJTalk: #{inspect(unknown)}"
    end

    :ok
  end

  defp validate_playback_mode!(opts) do
    case Keyword.fetch(opts, :playback_mode) do
      :error -> :ok
      {:ok, mode} when mode in [:auto, :file, :stdin] -> :ok
      {:ok, bad} -> raise ArgumentError, "invalid value for :playback_mode: #{inspect(bad)}"
    end
  end

  defp validate_timeout!(opts) do
    case Keyword.fetch(opts, :timeout) do
      :error -> :ok
      {:ok, t} when is_integer(t) and t >= 0 -> :ok
      {:ok, bad} -> raise ArgumentError, "invalid value for :timeout : #{inspect(bad)}"
    end
  end

  @doc """
  Synthesize `text` to a WAV file.
  Respects `:out` when provided; otherwise creates a unique path in the system temp dir.
  """
  @spec to_wav_file(binary, [synth_option()]) :: {:ok, Path.t()} | {:error, term}
  def to_wav_file(text, opts \\ []) when is_binary(text) do
    opts = validate_options!(opts)
    out = opts[:out] || OpenJTalk.Tempfile.tmp_path("wav")

    with {:ok, argv} <- OpenJTalk.Synth.args(out, opts),
         {:ok, txt, cleanup} <- OpenJTalk.Tempfile.write_tmp_text(text) do
      try do
        case OpenJTalk.Synth.run(argv ++ [txt], opts[:timeout]) do
          {:ok, _out} -> {:ok, out}
          {:error, _} = e -> e
        end
      after
        cleanup.()
      end
    end
  end

  @doc "Synthesize `text` and return RIFF/WAV bytes."
  @spec to_wav_binary(binary, [synth_option()]) :: {:ok, binary} | {:error, term}
  def to_wav_binary(text, opts \\ []) when is_binary(text) do
    opts = validate_options!(opts)

    OpenJTalk.Tempfile.with_tmp_path("wav", fn tmp ->
      with {:ok, _path} <- to_wav_file(text, Keyword.put(opts, :out, tmp)),
           {:ok, bin} <- File.read(tmp) do
        {:ok, bin}
      else
        {:error, _} = e -> e
      end
    end)
  end

  @doc """
  Play RIFF/WAV bytes already in memory (no temp files).

  Accepts the same `:playback_mode` and `:timeout` options as `say/2`.
  Use `playback_mode: :stdin` for diskless playback when a stdin-capable player is available.
  """
  @spec play_wav_binary(iodata(), [player_option()]) :: :ok | {:error, term}
  def play_wav_binary(wav_bytes, opts \\ []) do
    _ = validate_options!(opts)
    OpenJTalk.Player.play_wav_binary(wav_bytes, opts)
  end

  @doc "Play a WAV from a file path. See `play_wav_binary/2` for options."
  @spec play_wav_file(Path.t(), [player_option()]) :: :ok | {:error, term}
  def play_wav_file(path, opts \\ []) do
    _ = validate_options!(opts)
    OpenJTalk.Player.play_wav_file(path, opts)
  end

  @doc """
  Synthesize `text` with Open JTalk and play it.

  `:playback_mode` controls how playback occurs:
  - `:auto` (default) tries stdin first, then falls back to file playback.
  """
  @spec say(binary, [say_option()]) :: :ok | {:error, term}
  def say(text, opts \\ []) do
    opts = validate_options!(opts)
    mode = Keyword.get(opts, :playback_mode, :auto)
    do_say(text, mode, opts)
  end

  defp do_say(text, :stdin, opts) do
    with {:ok, wav} <- to_wav_binary(text, opts) do
      OpenJTalk.Player.play_wav_binary(wav, opts)
    end
  end

  defp do_say(text, :file, opts) do
    OpenJTalk.Tempfile.with_tmp_path("wav", fn out ->
      case to_wav_file(text, Keyword.put_new(opts, :out, out)) do
        {:ok, path} -> OpenJTalk.Player.play_wav_file(path, opts)
        {:error, _} = e -> e
      end
    end)
  end

  # :auto prefers stdin path (Player will fall back to file internally as needed)
  defp do_say(text, :auto, opts), do: do_say(text, :stdin, opts)

  @doc "Return useful information about the local Open J Talk setup."
  @spec info() :: {:ok, OpenJTalk.Info.info_map()}
  defdelegate info(), to: OpenJTalk.Info
end
