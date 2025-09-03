defmodule OpenJTalk.Say do
  @moduledoc false

  # Candidates in order of preference (Linux, Pulse, macOS, SoX)
  @players [
    {"aplay", ["-q"]},
    {"paplay", []},
    {"afplay", []},
    # sox
    {"play", ["-q"]}
  ]

  @spec say(binary) :: :ok | {:error, term}
  def say(text) when is_binary(text) do
    tmp = Path.join(System.tmp_dir!(), "jsay_#{System.unique_integer([:positive])}.wav")

    try do
      with :ok <- OpenJTalk.CLI.synth(text, to: tmp),
           {:ok, {player, args}} <- pick_player(),
           {_out, 0} <- System.cmd(player, args ++ [tmp], stderr_to_stdout: true) do
        :ok
      else
        {:error, _} = e -> e
        {_out, status} -> {:error, {:player_failed, status}}
      end
    after
      File.rm(tmp)
    end
  end

  @doc "Detect if any supported player is available (useful for tests)."
  def has_player?(), do: match?({:ok, _}, pick_player())

  defp pick_player do
    Enum.find_value(@players, {:error, :no_player_found}, fn {cmd, args} ->
      if System.find_executable(cmd), do: {:ok, {cmd, args}}, else: false
    end)
  end
end
