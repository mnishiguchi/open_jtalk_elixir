defmodule OpenJTalk.CLI do
  @moduledoc false

  @bin Application.app_dir(:open_jtalk_elixir, "priv/bin/open_jtalk")
  @dic Application.app_dir(:open_jtalk_elixir, "priv/dic")
  @voice Application.app_dir(:open_jtalk_elixir, "priv/voices/mei_normal.htsvoice")

  def synth(text, opts) when is_binary(text) and is_list(opts) do
    out = Keyword.fetch!(opts, :to)
    File.mkdir_p!(Path.dirname(out))

    with :ok <- ensure_exists(@bin, :binary_missing),
         :ok <- ensure_exists(@dic, :dictionary_missing),
         :ok <- ensure_exists(@voice, :voice_missing),
         {:ok, txt} <- write_textfile(text) do
      env =
        [
          {"LC_ALL", "C.UTF-8"}
        ] ++ ld_path_env()

      # direct exec; NO shell; give text file as last arg
      args = ["-x", @dic, "-m", @voice, "-ow", out, txt]
      timeout = Keyword.get(opts, :timeout, 20_000)

      task = Task.async(fn -> System.cmd(@bin, args, env: env, stderr_to_stdout: true) end)

      case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, {_out, 0}} ->
          File.rm_rf!(txt)
          :ok

        {:ok, {outmsg, status}} ->
          File.rm_rf!(txt)
          {:error, {:open_jtalk_exit, status, String.trim(outmsg)}}

        nil ->
          File.rm_rf!(txt)
          {:error, :timeout}
      end
    end
  end

  @spec synth_to_binary(binary) :: {:ok, binary} | {:error, term}
  def synth_to_binary(text) do
    out = Path.join(System.tmp_dir!(), "ojt_cli_#{System.unique_integer([:positive])}.wav")

    case synth(text, to: out) do
      :ok -> File.read(out)
      {:error, _} = e -> e
    end
  end

  # --- helpers ---

  defp ensure_exists(path, tag), do: if(File.exists?(path), do: :ok, else: {:error, {tag, path}})

  defp write_textfile(text) do
    p = Path.join(System.tmp_dir!(), "ojt_txt_#{System.unique_integer([:positive])}.txt")

    case File.write(p, text) do
      :ok -> {:ok, p}
      err -> err
    end
  end

  # If you ship shared libs in priv/lib, help the binary find them.
  defp ld_path_env do
    libdir = Application.app_dir(:open_jtalk_elixir, "priv/lib")

    if File.dir?(libdir) do
      [{"LD_LIBRARY_PATH", libdir <> ":" <> (System.get_env("LD_LIBRARY_PATH") || "")}]
    else
      []
    end
  end
end
