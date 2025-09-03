defmodule Mix.Tasks.OpenJtalk.Build do
  use Mix.Task

  @shortdoc "Builds Open JTalk + HTS Engine and installs binary/libs into priv/"

  @moduledoc """
  Builds Open JTalk from the sources downloaded by `mix open_jtalk.get`, then
  installs the resulting binary and (if needed) shared libs into `priv/`.

      mix open_jtalk.build

  Result:
    • priv/bin/open_jtalk
    • priv/lib/libHTSEngine.*  (if a shared lib is produced)

  Notes:
    • Host build by default. For cross-compiling (e.g. Nerves), export OPENJTALK_HOST
      (triplet) and toolchain env before running this task.
  """

  @hts_src_dir Path.join(["vendor", "hts_engine", "hts_engine_API-1.10"])
  @ojt_src_dir Path.join(["vendor", "open_jtalk", "open_jtalk-1.11"])
  @build_root Path.join(["vendor", "build"])
  @hts_prefix_r Path.join([@build_root, "hts_engine"])
  @ojt_prefix_r Path.join([@build_root, "open_jtalk"])

  @impl true
  def run(_args) do
    # Ensure sources/assets exist (downloads + extracts if missing)
    Mix.Task.run("open_jtalk.get")

    hts_prefix = Path.expand(@hts_prefix_r, File.cwd!())
    ojt_prefix = Path.expand(@ojt_prefix_r, File.cwd!())

    File.mkdir_p!(hts_prefix)
    File.mkdir_p!(ojt_prefix)
    File.mkdir_p!(priv!("bin"))
    File.mkdir_p!(priv!("lib"))

    build_hts_engine!(hts_prefix)
    build_open_jtalk!(hts_prefix, ojt_prefix)

    # Copy the binary to priv/bin
    bin_src = Path.join([ojt_prefix, "bin", "open_jtalk"])
    bin_dest = priv!("bin/open_jtalk")
    File.cp!(bin_src, bin_dest)
    File.chmod!(bin_dest, 0o755)

    # If a shared/static lib exists, copy it into priv/lib
    copy_any_libs!(hts_prefix)

    Mix.shell().info("""
    Built ✅
      • Binary: #{bin_dest}
      • Libs:   #{priv!("lib")} (if any)
    """)
  end

  # -- build steps -------------------------------------------------------------

  defp build_hts_engine!(prefix_abs) do
    already? =
      File.exists?(Path.join(prefix_abs, "lib")) or
        File.exists?(Path.join(prefix_abs, "include"))

    unless already? do
      host_flag = host_flag()

      # Run configure via `sh` so we don't depend on +x bit.
      configure_sh!(@hts_src_dir, ["--prefix=#{prefix_abs}"] ++ host_flag)

      run_cmd!(@hts_src_dir, "make", [])
      run_cmd!(@hts_src_dir, "make", ["install"])
    end
  end

  defp build_open_jtalk!(hts_prefix_abs, ojt_prefix_abs) do
    unless File.exists?(Path.join([ojt_prefix_abs, "bin", "open_jtalk"])) do
      host_flag = host_flag()

      configure_sh!(
        @ojt_src_dir,
        [
          "--with-hts-engine-header-path=#{Path.join(hts_prefix_abs, "include")}",
          "--with-hts-engine-library-path=#{Path.join(hts_prefix_abs, "lib")}",
          "--prefix=#{ojt_prefix_abs}"
        ] ++ host_flag
      )

      # 🔧 serialize to avoid mecab-naist-jdic race
      run_cmd!(@ojt_src_dir, "make", ["-j1"])
      run_cmd!(@ojt_src_dir, "make", ["-j1", "install"])
    end
  end

  # -- helpers ----------------------------------------------------------------

  defp host_flag do
    case System.get_env("OPENJTALK_HOST") do
      nil -> []
      host -> ["--host=#{host}"]
    end
  end

  defp configure_sh!(cwd, args) do
    # Quote args for the shell and run `sh -c './configure ...'`
    quoted =
      args
      |> Enum.map(&shell_quote/1)
      |> Enum.join(" ")

    run_cmd!(cwd, "sh", ["-c", "./configure #{quoted}"])
  end

  defp shell_quote(str) do
    # minimal safe single-quote
    "'" <> String.replace(str, "'", "'\"'\"'") <> "'"
  end

  defp copy_any_libs!(hts_prefix_abs) do
    src_lib_dir = Path.join(hts_prefix_abs, "lib")

    patterns = [
      # Linux
      Path.join(src_lib_dir, "libHTSEngine.so*"),
      # macOS
      Path.join(src_lib_dir, "libHTSEngine.dylib"),
      # versioned macOS
      Path.join(src_lib_dir, "libHTSEngine.*.dylib"),
      # static
      Path.join(src_lib_dir, "libHTSEngine.a")
    ]

    libs =
      patterns
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.uniq()

    Enum.each(libs, fn lib ->
      File.cp!(lib, Path.join(priv!("lib"), Path.basename(lib)))
    end)
  end

  defp run_cmd!(cwd, cmd, args, opts \\ []) do
    {out, status} = System.cmd(cmd, args, Keyword.merge([cd: cwd, stderr_to_stdout: true], opts))

    if status != 0 do
      Mix.raise("""
      Command failed in #{cwd}:
      $ #{Enum.join([cmd | args], " ")}
      #{out}
      """)
    end
  end

  defp priv!(sub), do: Path.join(Path.expand("priv", File.cwd!()), sub)
end
