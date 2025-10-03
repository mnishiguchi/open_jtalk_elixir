defmodule OpenJTalk.Assets do
  @moduledoc false
  # Resolve paths to the Open JTalk CLI, dictionary (`sys.dic`), and voice (`.htsvoice`).
  # Resolution order:
  #   1. Environment variables: `OPENJTALK_CLI`, `OPENJTALK_DICTIONARY_DIR`, `OPENJTALK_VOICE`
  #   2. Bundled files under `priv/`
  #   3. Common system locations (Homebrew, `/usr/*`, etc.)
  #
  # Results are cached in `:persistent_term`. Call `reset_cache/0` if the
  # environment changes at runtime.

  # Resolve priv paths at runtime (don’t bake build-host paths into the BEAM)
  # (Avoid compile-time interpolation of machine-specific paths.)
  defp priv_bin(), do: Application.app_dir(:open_jtalk_elixir, "priv/bin/open_jtalk")
  defp priv_dictionary_root(), do: Application.app_dir(:open_jtalk_elixir, "priv/dictionary")
  defp priv_voice_dir(), do: Application.app_dir(:open_jtalk_elixir, "priv/voices")

  @doc """
  Resolve the `open_jtalk` CLI path.
  """
  @spec resolve_bin() :: {:ok, Path.t()} | {:error, term()}
  def resolve_bin() do
    case :persistent_term.get({__MODULE__, :bin}, :unknown) do
      :unknown ->
        env = System.get_env("OPENJTALK_CLI")

        path =
          cond do
            is_binary(env) and File.exists?(env) -> env
            File.exists?(priv_bin()) -> priv_bin()
            path = System.find_executable("open_jtalk") -> path
            true -> nil
          end

        if path,
          do: put(:bin, path),
          else: {:error, {:binary_missing, [priv_bin(), "$PATH:open_jtalk"]}}

      path when is_binary(path) ->
        {:ok, path}
    end
  end

  @doc """
  Resolve the dictionary directory that contains `sys.dic`.

  If `path` is `nil`, consult env (`OPENJTALK_DICTIONARY_DIR`), then `priv/`, then
  system locations. If a `path` is provided, it must contain `sys.dic`.
  """
  @spec resolve_dictionary(nil | Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def resolve_dictionary(nil) do
    case :persistent_term.get({__MODULE__, :dictionary}, :unknown) do
      :unknown ->
        env = System.get_env("OPENJTALK_DICTIONARY_DIR")

        dic =
          cond do
            is_binary(env) and File.exists?(Path.join(env, "sys.dic")) -> env
            path = find_sysdic_under(priv_dictionary_root()) -> path
            path = find_system_naist_jdic() -> path
            true -> nil
          end

        if dic,
          do: put(:dictionary, dic),
          else: {:error, {:dictionary_missing, priv_dictionary_root()}}

      path when is_binary(path) ->
        {:ok, path}
    end
  end

  def resolve_dictionary(path) when is_binary(path) do
    if File.exists?(Path.join(path, "sys.dic")),
      do: {:ok, path},
      else: {:error, {:dictionary_missing, path}}
  end

  @doc """
  Resolve a `.htsvoice` file.

  If `path` is `nil`, consult env (`OPENJTALK_VOICE`), then `priv/`, then
  system locations.
  """
  @spec resolve_voice(nil | Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def resolve_voice(nil) do
    case :persistent_term.get({__MODULE__, :voice}, :unknown) do
      :unknown ->
        env = System.get_env("OPENJTALK_VOICE")

        voice =
          cond do
            is_binary(env) and File.exists?(env) -> env
            path = pick_first_htsvoice(priv_voice_dir()) -> path
            path = find_system_voice() -> path
            true -> nil
          end

        if voice, do: put(:voice, voice), else: {:error, {:voice_missing, priv_voice_dir()}}

      path when is_binary(path) ->
        {:ok, path}
    end
  end

  def resolve_voice(path) when is_binary(path) do
    if File.exists?(path), do: {:ok, path}, else: {:error, {:voice_missing, path}}
  end

  @doc """
  Clear cached paths so future `resolve_*` calls re-scan the filesystem/env.
  """
  @spec reset_cache() :: :ok
  def reset_cache() do
    for k <- [:bin, :dictionary, :voice], do: :persistent_term.erase({__MODULE__, k})
    :ok
  end

  defp put(key, val) do
    :persistent_term.put({__MODULE__, key}, val)
    {:ok, val}
  end

  # Keep this compile-guard-safe (no File.* in guards) and shallow for Credo.
  defp find_sysdic_under(root) do
    cond do
      dir_missing?(root) ->
        nil

      has_sys_dic?(root) ->
        root

      has_naist_sys_dic?(root) ->
        Path.join(root, "naist-jdic")

      true ->
        ls_for_sysdic(root)
    end
  end

  defp dir_missing?(root), do: not File.dir?(root)
  defp has_sys_dic?(root), do: File.exists?(Path.join(root, "sys.dic"))
  defp has_naist_sys_dic?(root), do: File.exists?(Path.join(root, "naist-jdic/sys.dic"))

  defp ls_for_sysdic(root) do
    case File.ls(root) do
      {:ok, entries} -> find_first_sysdic_dir(root, entries)
      {:error, _} -> nil
    end
  end

  defp find_first_sysdic_dir(root, entries) do
    entries
    |> Enum.map(&Path.join(root, &1))
    |> Enum.find(fn dir -> File.dir?(dir) and File.exists?(Path.join(dir, "sys.dic")) end)
  end

  defp find_system_naist_jdic() do
    brew = System.get_env("HOMEBREW_PREFIX") || "/usr/local"

    ([
       "/var/lib/mecab/dic/open-jtalk/naist-jdic",
       "/usr/lib/x86_64-linux-gnu/mecab/dic/open-jtalk/naist-jdic",
       "/usr/lib/aarch64-linux-gnu/mecab/dic/open-jtalk/naist-jdic",
       "/usr/local/lib/mecab/dic/open-jtalk/naist-jdic",
       "/usr/lib/mecab/dic/open-jtalk/naist-jdic",
       Path.join(brew, "share/open_jtalk/open_jtalk_dic_utf_8-1.11")
     ] ++ Path.wildcard(Path.join(brew, "Cellar/open-jtalk/*/dic/open_jtalk_dic_utf_8-1.11")))
    |> Enum.find(&File.exists?(Path.join(&1, "sys.dic")))
  end

  defp pick_first_htsvoice(dir) do
    if File.dir?(dir) do
      dir |> Path.join("**/*.htsvoice") |> Path.wildcard() |> List.first()
    end
  end

  defp find_system_voice() do
    brew = System.get_env("HOMEBREW_PREFIX") || "/usr/local"

    [
      "/usr/share/hts-voice/**/*.htsvoice",
      "/usr/local/share/hts-voice/**/*.htsvoice",
      Path.join(brew, "share/hts-voice/**/*.htsvoice")
    ]
    |> Enum.flat_map(&Path.wildcard/1)
    |> List.first()
  end
end
