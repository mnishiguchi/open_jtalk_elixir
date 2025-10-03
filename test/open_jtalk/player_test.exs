defmodule OpenJTalk.PlayerTest do
  # Audio playback can interfere if run concurrently on some CI/dev hosts.
  # Keep this file non-async so the :audio tests run serially.
  use ExUnit.Case, async: false

  @tag :audio
  test "say/2 synthesizes and plays via a file-based player, cleaning up the temp WAV" do
    if OpenJTalk.Player.available?() do
      assert :ok = OpenJTalk.say("これはファイル経由の再生テストです。")
    else
      IO.puts("⚠️ No file-based audio player available; skipping file playback test.")
      :ok
    end
  end

  @tag :audio
  test "play_wav_binary/2 streams WAV bytes over stdin when a stdin-capable player exists" do
    if OpenJTalk.Player.stdin_available?() do
      assert {:ok, wav} = OpenJTalk.to_wav_binary("これは標準入力経由の再生テストです。")
      assert :ok = OpenJTalk.play_wav_binary(wav, playback_mode: :stdin)
    else
      IO.puts("⚠️ No stdin-capable audio player available; skipping stdin playback test.")
      :ok
    end
  end

  @tag :audio
  @tag :tmp_dir
  test "play_wav_file/2 plays a previously synthesized WAV when a player exists", %{
    tmp_dir: tmp_dir
  } do
    if OpenJTalk.Player.available?() do
      out = Path.join(tmp_dir, "ojt_playback.wav")
      assert {:ok, ^out} = OpenJTalk.to_wav_file("これはファイル再生のテストです。", out: out)
      assert :ok = OpenJTalk.play_wav_file(out)
    else
      IO.puts("⚠️ No file-based audio player available; skipping play_wav_file test.")
      :ok
    end
  end
end
