defmodule Mix.Tasks.OpenJtalk.Clean do
  use Mix.Task
  @shortdoc "Removes fetched/built OpenJTalk artifacts"

  @targets ~w(vendor priv/bin priv/lib priv/dic priv/voices)

  @impl true
  def run(_args) do
    Enum.each(@targets, &File.rm_rf!/1)
    Mix.shell().info("OpenJTalk artifacts removed.")
  end
end
