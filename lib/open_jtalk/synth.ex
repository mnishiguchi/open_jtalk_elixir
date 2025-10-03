defmodule OpenJTalk.Synth do
  @moduledoc false
  # Build and run the `open_jtalk` CLI for synthesis.

  alias OpenJTalk.Assets

  @typedoc "Use the canonical top-level synth option type."
  @type option :: OpenJTalk.synth_option()

  @base_alpha 0.55
  @default_timeout 20_000

  @doc """
  Build the `open_jtalk` argv to synthesize into `wav_out`.

  Returns `{:ok, [bin | args]}` ready for `run/2`.
  """
  @spec args(Path.t(), [option()]) :: {:ok, [binary]} | {:error, term}
  def args(wav_out, user_opts) do
    opts = user_opts

    with {:ok, bin} <- Assets.resolve_bin(),
         {:ok, dic} <- Assets.resolve_dictionary(opts[:dictionary]),
         {:ok, voice} <- Assets.resolve_voice(opts[:voice]) do
      alpha = clamp(@base_alpha + (opts[:timbre] || 0.0), 0.0, 1.0)
      rate = clamp(opts[:rate] || 1.0, 0.5, 2.0)
      fm = clamp(opts[:pitch_shift] || 0, -24, 24)
      gain = clamp(opts[:gain] || 0, -20, 20)

      args =
        [
          "-x",
          dic,
          "-m",
          voice,
          "-ow",
          wav_out,
          "-a",
          to_string(alpha),
          "-r",
          to_string(rate),
          "-g",
          to_string(gain)
        ]
        |> maybe_add_fm(fm)

      {:ok, [bin | args]}
    end
  end

  @doc """
  Run the `open_jtalk` command via MuonTrap.

  Returns `{:ok, stdout}` or `{:error, {:open_jtalk_exit, status, trimmed_output}}`.
  """
  @spec run([binary], non_neg_integer() | nil) :: {:ok, binary} | {:error, term}
  def run([bin | args], timeout_ms) do
    env = [{"LC_ALL", "C"}] ++ ld_path_env()
    timeout = normalize_timeout(timeout_ms)

    case MuonTrap.cmd(bin, args, env: env, stderr_to_stdout: true, timeout: timeout) do
      {out, 0} -> {:ok, out}
      {out, status} -> {:error, {:open_jtalk_exit, status, String.trim(out)}}
    end
  end

  defp maybe_add_fm(args, 0), do: args
  defp maybe_add_fm(args, fm), do: args ++ ["-fm", to_string(fm)]

  # RPATH from the Makefile should already point to priv/lib.
  # LD_LIBRARY_PATH is a fallback if users partially static-link.
  defp ld_path_env() do
    libdir = Application.app_dir(:open_jtalk_elixir, "priv/lib")

    if File.dir?(libdir) do
      [
        {"LD_LIBRARY_PATH", libdir <> ":" <> (System.get_env("LD_LIBRARY_PATH") || "")},
        # macOS uses DYLD_LIBRARY_PATH; harmless elsewhere
        {"DYLD_LIBRARY_PATH", libdir <> ":" <> (System.get_env("DYLD_LIBRARY_PATH") || "")}
      ]
    else
      []
    end
  end

  defp normalize_timeout(nil), do: @default_timeout
  defp normalize_timeout(int) when is_integer(int) and int >= 0, do: int
  defp normalize_timeout(_), do: @default_timeout

  defp clamp(x, lo, hi) when is_number(x) and is_number(lo) and is_number(hi) do
    x |> min(hi) |> max(lo)
  end
end
