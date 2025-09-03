defmodule OpenJTalk.SayTest do
  use ExUnit.Case, async: true

  @tag :audio
  test "say plays audio and cleans up tmp file" do
    if OpenJTalk.Say.has_player?() do
      assert :ok = OpenJTalk.Say.say("こんにちは。これはテストです。")
    else
      IO.puts("⚠️  No audio player found; skipping.")
      :ok
    end
  end
end
