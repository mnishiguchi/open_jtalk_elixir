defmodule OpenJTalk.WavTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  defp mk_wav!(text) do
    {:ok, wav} = OpenJTalk.to_wav_binary(text)
    wav
  end

  test "concat_binaries/1 merges multiple OpenJTalk outputs into one WAV", %{tmp_dir: tmp} do
    a = mk_wav!("これは一つ目。")
    b = mk_wav!("これは二つ目。")
    c = mk_wav!("これは三つ目。")

    assert {:ok, merged} = OpenJTalk.Wav.concat_binaries([a, b, c])
    assert <<"RIFF", _::binary>> = merged

    out = Path.join(tmp, "merged.wav")
    :ok = File.write(out, merged)
    assert File.exists?(out)

    assert byte_size(merged) > byte_size(a)
    assert byte_size(merged) > byte_size(b)
    assert byte_size(merged) > byte_size(c)
  end

  test "concat_files/1 reads paths and merges", %{tmp_dir: tmp} do
    a = mk_wav!("ファイルその1")
    b = mk_wav!("ファイルその2")

    p1 = Path.join(tmp, "a.wav")
    p2 = Path.join(tmp, "b.wav")
    :ok = File.write(p1, a)
    :ok = File.write(p2, b)

    assert {:ok, merged} = OpenJTalk.Wav.concat_files([p1, p2])
    assert <<"RIFF", _::binary>> = merged
    assert byte_size(merged) > max(byte_size(a), byte_size(b))
  end

  test "concat_binaries/1 errors on empty input" do
    assert {:error, :empty_input} = OpenJTalk.Wav.concat_binaries([])
  end

  test "concat_binaries/1 errors when formats differ (byte_rate tweak)" do
    a = mk_wav!("同一フォーマットA")
    b = tweak_byte_rate(a, +1)

    # Tinkering byte_rate breaks internal consistency -> :inconsistent_format
    assert {:error, :inconsistent_format} = OpenJTalk.Wav.concat_binaries([a, b])
  end

  @tag :audio
  test "concatenated WAV can be played (stdin preferred, file fallback)", %{tmp_dir: tmp} do
    a = mk_wav!("これは一つ目。")
    b = mk_wav!("これは二つ目。")
    c = mk_wav!("これは三つ目。")
    assert {:ok, merged} = OpenJTalk.Wav.concat_binaries([a, b, c])
    assert <<"RIFF", _::binary>> = merged

    cond do
      OpenJTalk.Player.stdin_available?() ->
        assert :ok = OpenJTalk.play_wav_binary(merged, playback_mode: :stdin)

      OpenJTalk.Player.available?() ->
        path = Path.join(tmp, "merged_play.wav")
        :ok = File.write(path, merged)
        assert :ok = OpenJTalk.play_wav_file(path)

      true ->
        IO.puts("⚠️  No audio player available; skipping concatenated playback test.")
        assert true
    end
  end

  defp tweak_byte_rate(
         <<"RIFF", riff_size::little-32, "WAVE", "fmt ", fsize::little-32,
           fmt::binary-size(fsize), rest::binary>>,
         delta
       ) do
    <<
      af::little-16,
      ch::little-16,
      sr::little-32,
      br::little-32,
      ba::little-16,
      bps::little-16,
      tail::binary
    >> = fmt

    new_br = br + delta

    new_fmt =
      <<
        af::little-16,
        ch::little-16,
        sr::little-32,
        new_br::little-32,
        ba::little-16,
        bps::little-16,
        tail::binary
      >>

    <<"RIFF", riff_size::little-32, "WAVE", "fmt ", fsize::little-32, new_fmt::binary,
      rest::binary>>
  end
end
