defmodule Pled.RoundTripTest do
  use ExUnit.Case, async: false

  alias Pled.Commands.Decoder
  alias Pled.Commands.Encoder
  alias Pled.PluginModel

  @moduletag :tmp_dir

  setup do
    original = Application.get_env(:pled, :js_ast_runner)

    # Whitespace-insensitive stand-in for the real JS AST parser, so the
    # fingerprint absorbs the whitespace shifts of decode/encode wrapping.
    Application.put_env(:pled, :js_ast_runner, fn source, _opts ->
      {:ok, %{"normalized" => String.replace(source, ~r/\s+/, "")}}
    end)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:pled, :js_ast_runner)
      else
        Application.put_env(:pled, :js_ast_runner, original)
      end
    end)

    :ok
  end

  for fixture <- ["plugin.json", "small_plugin.json"] do
    test "decode then build round-trips #{fixture} to the same fingerprint", %{tmp_dir: tmp_dir} do
      remote = read_fixture(unquote(fixture))

      src_dir = Path.join(tmp_dir, "src")
      File.mkdir_p!(src_dir)
      File.write!(Path.join(src_dir, "plugin.json"), Jason.encode!(remote, pretty: true))
      Decoder.decode(remote, tmp_dir)

      tree_before = snapshot_tree(tmp_dir)

      ExUnit.CaptureIO.capture_io(fn ->
        send(self(), {:build, Encoder.build(src_dir: src_dir)})
      end)

      assert_received {:build, {:ok, payload, []}}

      assert PluginModel.fingerprint(payload) == PluginModel.fingerprint(remote)

      # build is pure: nothing in the workspace was written or changed
      assert snapshot_tree(tmp_dir) == tree_before
      refute File.exists?(Path.join(tmp_dir, "dist"))
    end
  end

  defp read_fixture(name) do
    :code.priv_dir(:pled)
    |> to_string()
    |> Path.join("examples/#{name}")
    |> File.read!()
    |> Jason.decode!()
  end

  defp snapshot_tree(dir) do
    dir
    |> Path.join("**")
    |> Path.wildcard(match_dot: true)
    |> Enum.sort()
    |> Enum.map(fn path ->
      if File.dir?(path) do
        {path, :dir}
      else
        {path, :crypto.hash(:sha256, File.read!(path))}
      end
    end)
  end
end
