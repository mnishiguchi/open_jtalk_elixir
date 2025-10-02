defmodule OpenJTalk.Runner do
  @moduledoc false
  # Internal: safe command runner with timeout & LD_LIBRARY_PATH fallback.

  # RPATH from your Makefile should already point to priv/lib.
  # LD_LIBRARY_PATH is a fallback if users partially static-link.
  def run([bin | args], timeout_ms \\ 20_000) do
    env = [{"LC_ALL", "C"}] ++ ld_path_env()
    timeout = normalize_timeout(timeout_ms)

    case MuonTrap.cmd(bin, args, env: env, stderr_to_stdout: true, timeout: timeout) do
      {out, 0} -> {:ok, out}
      {out, status} -> {:error, {:open_jtalk_exit, status, String.trim(out)}}
    end
  end

  def run_capture([bin | args], timeout_ms \\ 20_000) do
    case run([bin | args], timeout_ms) do
      {:ok, bytes} -> {:ok, bytes}
      other -> other
    end
  end

  defp normalize_timeout(:infinity), do: :infinity
  defp normalize_timeout(nil), do: 20_000
  defp normalize_timeout(int) when is_integer(int) and int >= 0, do: int
  defp normalize_timeout(_bad), do: 20_000

  def write_tmp_text(text) do
    path = Path.join(System.tmp_dir!(), "ojt-#{System.unique_integer([:positive])}.txt")

    case File.write(path, text <> "\n") do
      :ok -> {:ok, path, fn -> File.rm(path) end}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ld_path_env do
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
end
