defmodule OpenJTalk.TempfileTest do
  use ExUnit.Case, async: true

  test "with_tmp_path/2 cleans up the path afterwards" do
    returned_path =
      OpenJTalk.Tempfile.with_tmp_path("txt", fn path ->
        File.write!(path, "hello")
        assert File.exists?(path)
        path
      end)

    # The function returns whatever the callback returns, but the file is removed.
    assert is_binary(returned_path)
    refute File.exists?(returned_path)
  end

  test "write_tmp_text/1 returns cleanup fun that removes the file" do
    assert {:ok, path, cleanup} = OpenJTalk.Tempfile.write_tmp_text("abc")
    assert File.exists?(path)
    cleanup.()
    refute File.exists?(path)
  end
end
