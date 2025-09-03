defmodule Mix.Tasks.OpenJtalk.Get do
  use Mix.Task

  @shortdoc "Download Open JTalk source + UTF-8 dictionary + Mei voice into vendor/ and priv/"

  @moduledoc """
  Fetches the **standard** Open JTalk artifacts from SourceForge and puts them where our wrapper expects:

  - Source (for later building): `vendor/open_jtalk/` and `vendor/hts_engine/`
  - Dictionary (UTF-8): `priv/dic/`
  - Voice (Mei/normal): `priv/voices/mei_normal.htsvoice`

  No configuration, no env vars — just run:

      mix open_jtalk.get
  """

  # ---- Canonical URLs (no customization) ------------------------------------
  @openjtalk_src_url "https://sourceforge.net/projects/open-jtalk/files/Open%20JTalk/open_jtalk-1.11/open_jtalk-1.11.tar.gz/download"
  @hts_engine_src_url "https://sourceforge.net/projects/hts-engine/files/hts_engine%20API/hts_engine_API-1.10/hts_engine_API-1.10.tar.gz/download"
  @dic_url "https://sourceforge.net/projects/open-jtalk/files/Dictionary/open_jtalk_dic-1.11/open_jtalk_dic_utf_8-1.11.tar.gz/download"
  @mei_zip_url "https://sourceforge.net/projects/mmdagent/files/MMDAgent_Example/MMDAgent_Example-1.8/MMDAgent_Example-1.8.zip/download"
  @mei_inner "MMDAgent_Example-1.8/Voice/mei/mei_normal.htsvoice"

  @impl true
  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:public_key)
    {:ok, _} = Application.ensure_all_started(:ssl)
    {:ok, _} = Application.ensure_all_started(:inets)

    File.mkdir_p!(vendor!())
    File.mkdir_p!(priv!("dic"))
    File.mkdir_p!(priv!("voices"))

    # 1) Fetch & extract sources (Open JTalk + HTS Engine)
    src_tgz = Path.join(vendor!(), "open_jtalk-1.11.tar.gz")
    maybe_download!("Open JTalk source", @openjtalk_src_url, src_tgz)
    extract_tar_gz!(src_tgz, vendor!("open_jtalk"))

    hts_tgz = Path.join(vendor!(), "hts_engine_API-1.10.tar.gz")
    maybe_download!("HTS Engine source", @hts_engine_src_url, hts_tgz)
    extract_tar_gz!(hts_tgz, vendor!("hts_engine"))

    # 2) Fetch & install dictionary → priv/dic
    dic_tgz = Path.join(vendor!(), "open_jtalk_dic_utf_8-1.11.tar.gz")
    maybe_download!("UTF-8 dictionary", @dic_url, dic_tgz)
    tmp_dic = vendor!("dic_extract")
    extract_tar_gz!(dic_tgz, tmp_dic)
    copy_extracted_dic!(tmp_dic, priv!("dic"))

    # 3) Fetch & place Mei voice → priv/voices/mei_normal.htsvoice
    mei_zip = Path.join(vendor!(), "MMDAgent_Example-1.8.zip")
    maybe_download!("Mei voice (MMDAgent_Example-1.8.zip)", @mei_zip_url, mei_zip)
    tmp_mei = vendor!("mei_zip")
    extract_zip!(mei_zip, tmp_mei)

    # Fix: don't use File.exists? in a guard — check it normally first.
    candidate = Path.join(tmp_mei, @mei_inner)

    src_htsvoice =
      if File.exists?(candidate) do
        candidate
      else
        find_under!(tmp_mei, "mei_normal.htsvoice")
      end

    dest_htsvoice = priv!("voices/mei_normal.htsvoice")
    File.mkdir_p!(Path.dirname(dest_htsvoice))
    File.cp!(src_htsvoice, dest_htsvoice)

    Mix.shell().info("""
    \nAll set ✅
      • Source:     #{vendor!("open_jtalk")} #{exists_mark(vendor!("open_jtalk"))}
      • HTS Engine: #{vendor!("hts_engine")} #{exists_mark(vendor!("hts_engine"))}
      • Dictionary: #{priv!("dic")} #{exists_mark(priv!("dic"))}
      • Voice:      #{priv!("voices/mei_normal.htsvoice")} #{exists_mark(priv!("voices/mei_normal.htsvoice"))}
    """)
  end

  # ---- Paths ----------------------------------------------------------------
  defp vendor!(), do: Path.join(File.cwd!(), "vendor")
  defp vendor!(sub), do: Path.join(vendor!(), sub)

  defp priv!(), do: Path.join(File.cwd!(), "priv")
  defp priv!(sub), do: Path.join(priv!(), sub)

  # ---- Download / extract helpers -------------------------------------------
  defp maybe_download!(label, url, dest) do
    if File.exists?(dest) and File.stat!(dest).size > 0 do
      Mix.shell().info("• #{label}: already present (#{dest})")
      :ok
    else
      Mix.shell().info("• Downloading #{label}…")
      download!(url, dest)
      Mix.shell().info("  saved to #{dest}")
      :ok
    end
  end

  defp download!(url, dest) do
    req = {to_charlist(url), []}
    http_opts = [autoredirect: true]
    opts = [body_format: :binary]

    case :httpc.request(:get, req, http_opts, opts) do
      {:ok, {{_v, 200, _r}, _headers, body}} ->
        File.write!(dest, body)

      {:ok, {{_v, code, reason}, _headers, _body}} ->
        Mix.raise("Download failed (#{code} #{reason}) for #{url}")

      {:error, reason} ->
        Mix.raise("Download error for #{url}: #{inspect(reason)}")
    end
  end

  defp extract_tar_gz!(tgz_path, dest_dir) do
    File.mkdir_p!(dest_dir)

    case :erl_tar.extract(to_charlist(tgz_path), [:compressed, {:cwd, to_charlist(dest_dir)}]) do
      :ok -> :ok
      {:error, reason} -> Mix.raise("Failed to extract #{tgz_path}: #{inspect(reason)}")
    end
  end

  defp extract_zip!(zip_path, dest_dir) do
    File.mkdir_p!(dest_dir)

    case :zip.extract(to_charlist(zip_path), [{:cwd, to_charlist(dest_dir)}]) do
      {:ok, _files} -> :ok
      {:error, reason} -> Mix.raise("Failed to extract zip #{zip_path}: #{inspect(reason)}")
    end
  end

  # ---- Post-processing -------------------------------------------------------
  defp copy_extracted_dic!(src_root, dest_dic) do
    # Find inner extracted dictionary folder and copy its CONTENTS -> priv/dic
    subdirs =
      src_root
      |> File.ls!()
      |> Enum.map(&Path.join(src_root, &1))
      |> Enum.filter(&File.dir?/1)

    chosen =
      Enum.find(subdirs, fn p ->
        b = Path.basename(p)
        String.contains?(b, "open_jtalk_dic") or String.contains?(b, "dic")
      end) ||
        List.first(subdirs) ||
        Mix.raise("Could not find extracted dictionary directory under #{src_root}")

    File.rm_rf!(dest_dic)
    File.mkdir_p!(dest_dic)

    for entry <- File.ls!(chosen) do
      from = Path.join(chosen, entry)
      to = Path.join(dest_dic, entry)

      case File.cp_r(from, to) do
        {:ok, _} -> :ok
        {:error, reason, file} -> Mix.raise("Failed to copy #{file}: #{inspect(reason)}")
      end
    end
  end

  defp find_under!(root, filename) do
    Path.wildcard(Path.join([root, "**", "*"]))
    |> Enum.find(&(Path.basename(&1) == filename))
    |> case do
      nil -> Mix.raise("Could not find #{filename} under #{root}")
      path -> path
    end
  end

  defp exists_mark(path), do: if(File.exists?(path), do: "✓", else: "—")
end
