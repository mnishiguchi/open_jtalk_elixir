defmodule OpenJTalk.Tempfile do
  @moduledoc false
  # Temporary file utilities for synthesis and playback.

  @doc "Generate a unique temp file path with the given extension (e.g., `wav`, `txt`)."
  @spec tmp_path(binary) :: Path.t()
  def tmp_path(ext) when is_binary(ext) do
    Path.join(System.tmp_dir!(), "ojt-#{System.unique_integer([:positive])}.#{ext}")
  end

  @doc """
  Execute a function with a fresh tmp path; always cleans up afterwards.

  ## Example
      with_tmp_path("wav", fn path ->
        File.write!(path, <<1,2,3>>)
        :ok
      end)
  """
  @spec with_tmp_path(binary, (Path.t() -> any)) :: any
  def with_tmp_path(ext, fun) when is_function(fun, 1) do
    path = tmp_path(ext)

    try do
      fun.(path)
    after
      File.rm(path)
    end
  end

  @doc """
  Write `text` to a temporary `*.txt` file and append a trailing newline.

  Returns `{:ok, path, cleanup_fun}` where `cleanup_fun/0` removes the file.
  """
  @spec write_tmp_text(binary) :: {:ok, Path.t(), (-> any)} | {:error, term}
  def write_tmp_text(text) when is_binary(text) do
    path = tmp_path("txt")

    case File.write(path, text <> "\n") do
      :ok -> {:ok, path, fn -> File.rm(path) end}
      {:error, reason} -> {:error, reason}
    end
  end
end
