defmodule OpenJTalkTest do
  use ExUnit.Case, async: true

  @tag :tmp_dir
  test "to_wav_file/2 writes a WAV to the given path", %{tmp_dir: tmp_dir} do
    out = Path.join(tmp_dir, "ojt_#{System.unique_integer([:positive])}.wav")
    assert {:ok, ^out} = OpenJTalk.to_wav_file("テストです。", out: out)
    assert File.exists?(out)
    assert {:ok, <<"RIFF", _::binary>>} = File.read(out)
    assert File.stat!(out).size > 44
  end

  @tag :tmp_dir
  test "to_wav_file/2 overwrites an existing file at :out", %{tmp_dir: tmp_dir} do
    out = Path.join(tmp_dir, "already_there.wav")
    :ok = File.write(out, "<<not-a-wave>>")
    assert {:ok, ^out} = OpenJTalk.to_wav_file("上書きのテストです。", out: out)
    assert {:ok, <<"RIFF", _::binary>>} = File.read(out)
  end

  test "to_wav_binary/2 returns RIFF WAV bytes" do
    assert {:ok, <<"RIFF", _::binary>>} = OpenJTalk.to_wav_binary("こんにちは")
  end
end
