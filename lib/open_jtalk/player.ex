defmodule OpenJTalk.Player do
  @moduledoc false
  # Audio playback helpers for WAV produced by OpenJTalk.

  @type playback_mode :: OpenJTalk.playback_mode()

  @type option :: OpenJTalk.player_option()

  # File-based player candidates (path + args).
  @file_players [
    {"aplay", ["-q"]},
    {"paplay", []},
    {"afplay", []},
    {"play", ["-q"]}
  ]

  # Stdin-capable candidates (WAV over stdin). Order matters.
  @stdin_players [
    {"aplay", ["-q", "-"]},
    {"play", ["-q", "-t", "wav", "-"]},
    {"afplay", ["-"]},
    {"paplay", ["-"]}
  ]

  @default_timeout 20_000

  @doc "Returns `true` if a supported file-based player is available."
  @spec available?() :: boolean()
  def available?(), do: match?({:ok, _}, resolve_player())

  @doc "Returns `true` if a stdin-capable WAV player is available."
  @spec stdin_available?() :: boolean()
  def stdin_available?(), do: match?({:ok, _}, resolve_player_stdin())

  @doc "Uniform info about the system audio player."
  @spec info() :: %{path: String.t() | nil, source: :system | :none}
  def info() do
    case resolve_player() do
      {:ok, {_cmd, _args, path}} -> %{path: path, source: :system}
      {:error, :no_player_found} -> %{path: nil, source: :none}
    end
  end

  @doc "Play a WAV from a file path."
  @spec play_wav_file(Path.t(), [option()]) :: :ok | {:error, term}
  def play_wav_file(path, opts \\ []) do
    case resolve_player() do
      {:ok, {cmd, args, _abs}} ->
        case run_player(cmd, args ++ [path], opts) do
          {_out, 0} -> :ok
          {out, status} -> {:error, {:player_failed, status, String.trim(out)}}
        end

      {:error, _} = e ->
        e
    end
  end

  @doc """
  Play WAV bytes already in memory (no temp files).

  Honors `:playback_mode`. The input must be valid RIFF/WAV (as returned by
  `OpenJTalk.to_wav_binary/2`).
  """
  @spec play_wav_binary(iodata(), [option()]) :: :ok | {:error, term}
  def play_wav_binary(wav_bytes, opts \\ []) do
    mode = Keyword.get(opts, :playback_mode, :auto)

    case mode do
      :file ->
        play_binary_via_tempfile(IO.iodata_to_binary(wav_bytes), opts)

      :stdin ->
        do_play_stdin(wav_bytes, opts)

      :auto ->
        # stdin-first; fall back to tempfile if stdin unavailable/unsupported
        do_play_stdin(wav_bytes, opts)
    end
  end

  # Always falls back to tempfile if stdin playback isn't available or fails.
  defp do_play_stdin(wav_bytes, opts) do
    bin = IO.iodata_to_binary(wav_bytes)

    case resolve_player_stdin() do
      {:ok, {cmd, args}} ->
        try do
          case run_player(cmd, args, opts, bin) do
            {_out, 0} -> :ok
            {out, status} -> {:error, {:player_failed, status, String.trim(out)}}
          end
        rescue
          ArgumentError ->
            play_binary_via_tempfile(bin, opts)
        end

      {:error, :no_stdin_player} ->
        play_binary_via_tempfile(bin, opts)
    end
  end

  defp play_binary_via_tempfile(bin, opts) do
    path = tmp_path("wav")

    try do
      case File.write(path, bin) do
        :ok -> play_wav_file(path, opts)
        {:error, reason} -> {:error, {:write_failed, reason}}
      end
    after
      File.rm(path)
    end
  end

  # Standardized MuonTrap call for players (builds timeout/stderr options).
  # Optional `stdin_bin` streams WAV bytes when provided.
  defp run_player(cmd, args, opts, stdin_bin \\ nil) do
    timeout = normalize_timeout(Keyword.get(opts, :timeout, @default_timeout))
    base = [stderr_to_stdout: true, timeout: timeout]
    mu_opts = if is_binary(stdin_bin), do: Keyword.put(base, :stdin, stdin_bin), else: base
    MuonTrap.cmd(cmd, args, mu_opts)
  end

  defp resolve_player() do
    Enum.find_value(@file_players, {:error, :no_player_found}, fn {cmd, args} ->
      case System.find_executable(cmd) do
        nil -> false
        path -> {:ok, {cmd, args, path}}
      end
    end)
  end

  defp resolve_player_stdin() do
    Enum.find_value(@stdin_players, {:error, :no_stdin_player}, fn {cmd, args} ->
      case System.find_executable(cmd) do
        nil -> false
        _ -> {:ok, {cmd, args}}
      end
    end)
  end

  defp tmp_path(ext),
    do: Path.join(System.tmp_dir!(), "ojt-#{System.unique_integer([:positive])}.#{ext}")

  defp normalize_timeout(nil), do: @default_timeout
  defp normalize_timeout(int) when is_integer(int) and int >= 0, do: int
  defp normalize_timeout(_bad), do: @default_timeout
end
