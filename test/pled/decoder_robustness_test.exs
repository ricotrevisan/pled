defmodule Pled.DecoderRobustnessTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Pled.Commands.Decoder
  alias Pled.Commands.Encoder
  alias Pled.Commands.Pull

  @moduletag :tmp_dir

  # A partially configured plugin: no display names, no code sections.
  @wip_plugin %{
    "name" => "WIP Plugin",
    "plugin_elements" => %{
      "AAA" => %{
        "actions" => %{"ABB" => %{"caption" => nil}},
        "fields" => %{"AAF" => %{"rank" => 0}}
      }
    },
    "plugin_actions" => %{"AAK" => %{}}
  }

  describe "pull on a work-in-progress plugin" do
    setup %{tmp_dir: tmp_dir} do
      previous = %{
        cookie: System.get_env("BUBBLE_COOKIE"),
        plugin_id: System.get_env("PLUGIN_ID"),
        req_options: Application.get_env(:pled, :req_options),
        adapter_fun: Application.get_env(:pled, :test_adapter_fun),
        snapshot_file: Application.get_env(:pled, :src_snapshot_file)
      }

      System.put_env("BUBBLE_COOKIE", "test-cookie")
      System.put_env("PLUGIN_ID", "1234x5678")
      Application.put_env(:pled, :req_options, adapter: Pled.TestAdapter)

      Application.put_env(:pled, :test_adapter_fun, fn request ->
        {request, %Req.Response{status: 200, body: @wip_plugin}}
      end)

      Application.put_env(:pled, :src_snapshot_file, Path.join(tmp_dir, ".src.json"))

      cwd = File.cwd!()
      File.cd!(tmp_dir)

      on_exit(fn ->
        File.cd!(cwd)
        restore_env("BUBBLE_COOKIE", previous.cookie)
        restore_env("PLUGIN_ID", previous.plugin_id)
        restore_app_env(:req_options, previous.req_options)
        restore_app_env(:test_adapter_fun, previous.adapter_fun)
        restore_app_env(:src_snapshot_file, previous.snapshot_file)
      end)

      :ok
    end

    test "pull succeeds with key-fallback names and placeholder files, and the tree encodes" do
      capture_io(fn -> send(self(), {:pull, Pull.run([])}) end)
      assert_received {:pull, :ok}

      # key-derived directory names instead of a crash on missing display
      element_dir = "src/elements/aaa-AAA"
      assert File.dir?(element_dir)
      assert File.dir?("src/actions/aak-AAK")

      # missing element code sections become empty placeholders
      for js <- ["initialize.js", "update.js", "reset.js", "preview.js"] do
        assert File.read!(Path.join(element_dir, js)) == ""
      end

      # element action without code gets a non-empty placeholder (the encoder
      # rejects empty action files); caption falls back to the key
      assert File.read!(Path.join(element_dir, "actions/abb-ABB.js")) =~ "missing action code"

      # field without caption falls back to the key
      assert File.read!(Path.join(element_dir, "fields.txt")) == "AAF (AAF)"

      # plugin action without code sections: json written, no server/client js
      assert File.exists?("src/actions/aak-AAK/aak.json")
      refute File.exists?("src/actions/aak-AAK/server.js")
      refute File.exists?("src/actions/aak-AAK/client.js")

      # the resulting tree encodes without crashing
      capture_io(fn -> send(self(), {:build, Encoder.build(src_dir: "src")}) end)
      assert_received {:build, {:ok, payload, _issues}}
      assert Map.has_key?(payload["plugin_elements"], "AAA")

      # absent remote code sections are not invented by the encoder
      aak = payload["plugin_actions"]["AAK"]
      refute Map.has_key?(aak["code"] || %{}, "server")
      refute Map.has_key?(aak["code"] || %{}, "client")

      # the element action placeholder becomes its code fn
      abb_fn = get_in(payload, ["plugin_elements", "AAA", "actions", "ABB", "code", "fn"])
      assert abb_fn =~ "missing action code"
    end

    test "pull aborts with an error naming the file when a decode write fails" do
      # a file where the elements directory should be makes the decode fail
      File.mkdir_p!("src")
      File.write!("src/elements", "in the way")

      output = capture_io(fn -> send(self(), {:pull, Pull.run([])}) end)

      assert_received {:pull, {:error, message}}
      assert message =~ "src/elements"
      assert output =~ "Pull failed"
    end
  end

  describe "failed writes during decode" do
    test "abort with an error naming the file", %{tmp_dir: tmp_dir} do
      File.mkdir_p!(Path.join(tmp_dir, "src"))
      File.write!(Path.join(tmp_dir, "src/plugin.json"), Jason.encode!(@wip_plugin))
      # a file where the elements directory should be makes every write below fail
      File.write!(Path.join(tmp_dir, "src/elements"), "in the way")

      assert {:error, message} = Decoder.decode(@wip_plugin, tmp_dir)
      assert message =~ "src/elements"
    end
  end

  describe "encoding a tree with missing files" do
    setup %{tmp_dir: tmp_dir} do
      priv_dir = :code.priv_dir(:pled) |> to_string()

      plugin_data =
        File.read!(Path.join(priv_dir, "examples/small_plugin.json")) |> Jason.decode!()

      src_dir = Path.join(tmp_dir, "src")
      File.mkdir_p!(src_dir)
      File.write!(Path.join(src_dir, "plugin.json"), Jason.encode!(plugin_data, pretty: true))
      Decoder.decode(plugin_data, tmp_dir)

      {:ok, src_dir: src_dir}
    end

    test "missing element js file fails the encode command naming the file and the remedy", %{
      src_dir: src_dir,
      tmp_dir: tmp_dir
    } do
      File.rm!(Path.join(src_dir, "elements/tiptap-AAC/initialize.js"))

      cwd = File.cwd!()
      File.cd!(tmp_dir)

      try do
        output = capture_io(fn -> send(self(), {:encode, Encoder.encode()}) end)

        assert_received {:encode, {:error, message}}
        assert message =~ "initialize.js"
        assert message =~ "pled pull"
        assert output =~ "Encoding failed"
      after
        File.cd!(cwd)
      end
    end

    test "missing action js file with a json code section fails naming the file", %{
      src_dir: src_dir
    } do
      File.rm!(Path.join(src_dir, "actions/generate-jwt-key-AEK/server.js"))

      capture_io(fn -> send(self(), {:build, Encoder.build(src_dir: src_dir)}) end)

      assert_received {:build, {:error, message}}
      assert message =~ "server.js"
      assert message =~ "pled pull"
    end

    test "missing element json fails naming the file", %{src_dir: src_dir} do
      File.rm!(Path.join(src_dir, "elements/tiptap-AAC/AAC.json"))

      capture_io(fn -> send(self(), {:build, Encoder.build(src_dir: src_dir)}) end)

      assert_received {:build, {:error, message}}
      assert message =~ "AAC.json"
      assert message =~ "pled pull"
    end

    test "missing action json fails naming the action directory", %{src_dir: src_dir} do
      File.rm!(Path.join(src_dir, "actions/generate-jwt-key-AEK/generate-jwt-key.json"))

      capture_io(fn -> send(self(), {:build, Encoder.build(src_dir: src_dir)}) end)

      assert_received {:build, {:error, message}}
      assert message =~ "generate-jwt-key-AEK"
      assert message =~ "generate-jwt-key.json"
      assert message =~ "pled pull"
    end
  end

  describe "an action code section without a body" do
    @bodyless_plugin %{
      "name" => "WIP Plugin",
      "plugin_actions" => %{
        "AAK" => %{
          "display" => "Sign token",
          "code" => %{"server" => %{"package_used" => true}}
        }
      }
    }

    test "decodes without a js file and encodes back unchanged", %{tmp_dir: tmp_dir} do
      src_dir = Path.join(tmp_dir, "src")
      File.mkdir_p!(src_dir)
      File.write!(Path.join(src_dir, "plugin.json"), Jason.encode!(@bodyless_plugin))

      assert :ok = Decoder.decode(@bodyless_plugin, tmp_dir)
      refute File.exists?(Path.join(src_dir, "actions/sign-token-AAK/server.js"))

      capture_io(fn -> send(self(), {:build, Encoder.build(src_dir: src_dir)}) end)

      assert_received {:build, {:ok, payload, []}}
      assert payload["plugin_actions"]["AAK"]["code"] == %{"server" => %{"package_used" => true}}
    end
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)

  defp restore_app_env(key, nil), do: Application.delete_env(:pled, key)
  defp restore_app_env(key, value), do: Application.put_env(:pled, key, value)
end
