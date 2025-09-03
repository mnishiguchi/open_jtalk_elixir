defmodule OpenJTalk.CliTest do
  use ExUnit.Case, async: true

  test "CLI synth writes a wav" do
    out = Path.join(System.tmp_dir!(), "ojt_cli_#{System.unique_integer([:positive])}.wav")
    assert :ok = OpenJTalk.CLI.synth("テストです。", to: out)
    assert File.exists?(out)
    assert {:ok, <<"RIFF", _::binary>>} = File.read(out)
    assert File.stat!(out).size > 44
  end

  test "synth_to_binary returns a RIFF wav" do
    assert {:ok, <<"RIFF", _::binary>>} = OpenJTalk.CLI.synth_to_binary("こんにちは")
  end
end
