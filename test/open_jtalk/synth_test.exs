defmodule OpenJTalk.SynthTest do
  use ExUnit.Case, async: true

  defp flag_value!(argv, flag) do
    case Enum.find_index(argv, &(&1 == flag)) do
      nil -> flunk("missing flag #{inspect(flag)} in #{inspect(argv)}")
      idx -> Enum.at(argv, idx + 1)
    end
  end

  defp parse_float!(str) do
    case Float.parse(str) do
      {v, ""} -> v
      _ -> flunk("not a float: #{inspect(str)}")
    end
  end

  test "args/2 clamps timbre, rate, pitch_shift, and gain" do
    # Exaggerated inputs to force clamping on all adjustable parameters.
    opts = [timbre: 10.0, rate: 99.0, pitch_shift: -999, gain: 999]
    out = Path.join(System.tmp_dir!(), "ojt-args-test.wav")

    assert {:ok, [_bin | argv]} = OpenJTalk.Synth.args(out, opts)

    # Sanity: required flags are present
    assert "-x" in argv
    assert "-m" in argv
    assert "-ow" in argv
    assert "-a" in argv
    assert "-r" in argv
    assert "-g" in argv

    # Output path is wired correctly
    assert flag_value!(argv, "-ow") == out

    # Exact clamped values
    # timbre affects alpha: base 0.55 + 10.0 -> clamped to 1.0
    assert parse_float!(flag_value!(argv, "-a")) == 1.0
    # rate 99.0 -> clamped to 2.0
    assert parse_float!(flag_value!(argv, "-r")) == 2.0
    # gain 999 -> clamped to 20.0
    assert parse_float!(flag_value!(argv, "-g")) == 20.0

    # pitch_shift -999 -> clamped to -24 and included via -fm
    fm_index = Enum.find_index(argv, &(&1 == "-fm")) || flunk("missing -fm in #{inspect(argv)}")
    assert Enum.at(argv, fm_index + 1) == "-24"
  end

  test "args/2 omits -fm when pitch_shift is exactly 0" do
    out = Path.join(System.tmp_dir!(), "ojt-args-nofm.wav")
    assert {:ok, [_bin | argv]} = OpenJTalk.Synth.args(out, pitch_shift: 0)
    refute "-fm" in argv
  end

  test "args/2 clamps pitch_shift upper bound to 24" do
    out = Path.join(System.tmp_dir!(), "ojt-args-maxfm.wav")
    assert {:ok, [_bin | argv]} = OpenJTalk.Synth.args(out, pitch_shift: 999)

    i = Enum.find_index(argv, &(&1 == "-fm")) || flunk("missing -fm in #{inspect(argv)}")
    assert Enum.at(argv, i + 1) == "24"
  end
end
