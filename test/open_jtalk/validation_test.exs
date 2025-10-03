defmodule OpenJTalk.ValidationTest do
  use ExUnit.Case, async: true

  test "validate_options!/1 accepts known options and returns them unchanged" do
    opts = [
      timbre: 0.1,
      pitch_shift: -2,
      rate: 1.2,
      gain: 3,
      voice: "/tmp/voice.htsvoice",
      dictionary: "/tmp/dic",
      timeout: 10_000,
      playback_mode: :auto,
      out: "/tmp/x.wav"
    ]

    assert ^opts = OpenJTalk.validate_options!(opts)
  end

  test "validate_options!/1 rejects unknown keys" do
    assert_raise ArgumentError, ~r/unknown option\(s\) for OpenJTalk/, fn ->
      OpenJTalk.validate_options!(foo: :bar)
    end
  end

  test "validate_options!/1 rejects bad :playback_mode values" do
    assert_raise ArgumentError, ~r/invalid value for :playback_mode/, fn ->
      OpenJTalk.validate_options!(playback_mode: :stream)
    end
  end

  test "validate_options!/1 rejects negative :timeout" do
    assert_raise ArgumentError, ~r/invalid value for :timeout/, fn ->
      OpenJTalk.validate_options!(timeout: -1)
    end
  end
end
