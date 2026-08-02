defmodule Pled.EndToEndTest do
  use ExUnit.Case, async: false

  alias Pled.Commands.Encoder
  alias Pled.Commands.Decoder

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    # simulate pull
    example_path = "./priv/examples/plugin.json"
    File.mkdir_p!(Path.join(tmp_dir, "src"))
    File.cp(example_path, Path.join([tmp_dir, "src", "plugin.json"]))

    src_path = Path.join([tmp_dir, "src"])
    dist_path = Path.join([tmp_dir, "dist"])
    plugin_data = File.read!(Path.join(src_path, "plugin.json"))

    cwd = File.cwd!()
    File.cd!(tmp_dir)

    plugin_data
    |> Jason.decode!()
    |> Decoder.decode()

    Encoder.encode()

    File.cd!(cwd)

    dist_json = dist_path |> Path.join("plugin.json") |> File.read!() |> Jason.decode!()

    {:ok, src_path: src_path, dist_path: dist_path, dist_json: dist_json}
  end

  test "decode/1 extracts 5 root files", %{src_path: src_path} do
    assert Enum.sort(File.ls!(src_path)) ==
             Enum.sort([
               "plugin.json",
               "shared.html",
               "elements",
               "actions"
             ])
  end

  describe "plugin_actions" do
    test "src/actions has 1 action", %{src_path: src_path, dist_json: dist_json} do
      actions_path = Path.join(src_path, "actions")
      assert File.ls!(actions_path) == ["generate-jwt-key-AEK"]

      assert Map.has_key?(dist_json, "plugin_actions") == true
      assert Map.has_key?(dist_json["plugin_actions"], "AEK") == true
      assert Enum.count(dist_json["plugin_actions"]) == 1
    end

    test "src/actions/action decoded action exists in encoded json ", %{
      src_path: src_path,
      dist_json: dist_json
    } do
      action_path = Path.join([src_path, "actions", "generate-jwt-key-AEK"])
      assert Enum.sort(File.ls!(action_path)) == ["generate-jwt-key.json", "server.js"]
      src_server_js = action_path |> Path.join("server.js") |> File.read!()

      server_js = get_in(dist_json, ["plugin_actions", "AEK", "code", "server", "fn"])
      # the fixture's server fn is not async; the wrapper is preserved as-is
      assert String.starts_with?(server_js, "function(properties, context) {")

      assert server_js =~ String.slice(src_server_js, 0..10)
    end

    test "src/actions/action/action.json keeps only the server fn signature", %{
      src_path: src_path
    } do
      action_path = Path.join([src_path, "actions", "generate-jwt-key-AEK"])

      action_json =
        action_path
        |> Path.join("generate-jwt-key.json")
        |> File.read!()
        |> Jason.decode!()

      assert action_json["code"]["server"]["fn"] == "function(properties, context)"
      assert Map.has_key?(action_json["code"], "client") == false
    end
  end

  describe "plugin_elements" do
    test "src/elements has element", %{src_path: src_path} do
      elements_path = Path.join(src_path, "elements")
      assert File.ls!(elements_path) == ["tiptap-AAC"]
    end

    test "src/elements/element has the correct amount of files", %{src_path: src_path} do
      element_path = Path.join([src_path, "elements", "tiptap-AAC"])

      assert Enum.sort(File.ls!(element_path)) ==
               Enum.sort([
                 "reset.js",
                 "preview.js",
                 "update.js",
                 "initialize.js",
                 "fields.txt",
                 "actions",
                 "AAC.json"
               ])
    end

    test "src/elements/element/.json doesn't have repeated keys", %{src_path: src_path} do
      element_path = Path.join([src_path, "elements", "tiptap-AAC"])

      json =
        Path.wildcard(element_path <> "/*.json")
        |> List.first()
        |> File.read!()
        |> Jason.decode!()

      refute Map.has_key?(json, "code")
    end

    test "dist/plugin.json has element code", %{src_path: src_path, dist_json: dist_json} do
      actions = ["initialize", "update", "reset", "preview"]
      element_map = get_in(dist_json, ["plugin_elements", "AAC", "code"])

      decoded_element_path = Path.join([src_path, "elements", "tiptap-AAC"])

      Enum.each(actions, fn action ->
        assert Map.has_key?(element_map, action)
        assert Map.has_key?(element_map[action], "fn")
        action_js = get_in(element_map, [action, "fn"])

        decoded_action_js =
          Path.join(decoded_element_path, action <> ".js") |> File.read!()

        assert String.starts_with?(action_js, "function(")
        assert action_js =~ String.slice(decoded_action_js, 0..10)
      end)
    end

    test "plugin actions work", %{src_path: src_path, dist_json: dist_json} do
      element_json =
        Path.join([
          src_path,
          "elements",
          "tiptap-AAC",
          "AAC.json"
        ])
        |> File.read!()
        |> Jason.decode!()

      action_path =
        Path.join([
          src_path,
          "elements",
          "tiptap-AAC",
          "actions",
          "table-toggle-header-row-ACp.js"
        ])

      action_js = File.read!(action_path)
      assert String.starts_with?(action_js, "if (!instance.data.editor_is_ready)\n ")

      assert element_json["actions"]["ACp"] == %{
               "caption" => "Table toggle header row"
             }

      action =
        get_in(dist_json, ["plugin_elements", "AAC", "actions", "ACp"])

      assert action["caption"] == "Table toggle header row"
      code = action["code"]["fn"]
      assert String.starts_with?(code, "function(instance, properties, context) {")
      assert code =~ "instance.data.editor.chain().focus().toggleHeaderRow().run();"
    end

    test "src/elements/element/* doesn't have repeated keys", %{src_path: src_path} do
      element_actions_path = Path.join([src_path, "elements", "tiptap-AAC", "actions"])

      assert Enum.sort(File.ls!(element_actions_path)) ==
               Enum.sort([
                 "task-list-ABS.js",
                 "table-split-cell-ACy.js",
                 "h3-AAx.js",
                 "horizontal-rule-ABO.js",
                 "table-toggle-header-column-ACq.js",
                 "align-text-ACd.js",
                 "clear-contents-ABp.js",
                 "italic-AAj.js",
                 "table-delete-row-ACw.js",
                 "set-hard-break-AGC.js",
                 "unset-color-AFZ.js",
                 "select-entire-block-AFi.js",
                 "table-add-column-after-ACs.js",
                 "table-add-row-after-ACu.js",
                 "focus-ABr.js",
                 "insert-content-ADG.js",
                 "underline-ADB.js",
                 "set-font-family-AFS.js",
                 "set-color-AFX.js",
                 "insert-table-ACl.js",
                 "indent-item-ABH.js",
                 "add-youtube-ADI.js",
                 "table-merge-cells-ACz.js",
                 "h5-AAz.js",
                 "table-merge-or-split-ADA.js",
                 "h1-AAp.js",
                 "strikethrough-AAm.js",
                 "insert-image-ACD.js",
                 "highlight-ACi.js",
                 "table-delete-column-ACx.js",
                 "table-add-column-before-ACt.js",
                 "numbered-list-ABE.js",
                 "bold-AAh.js",
                 "set-content-ACW.js",
                 "outdent-item-ABI.js",
                 "bullet-list-ABC.js",
                 "h2-AAv.js",
                 "table-add-row-before-ACv.js",
                 "h6-ABA.js",
                 "delete-table-ACr.js",
                 "table-toggle-header-row-ACp.js",
                 "clear-headings-AEf.js",
                 "unset-font-family-AFU.js",
                 "remove-link-ACR.js",
                 "blockquote-ABK.js",
                 "set-link-ACN.js",
                 "h4-AAy.js",
                 "code-block-ABN.js"
               ])
    end

    test "element fields are preserved through encode/decode cycle", %{
      src_path: src_path,
      dist_json: dist_json
    } do
      # Check that fields.txt was created during decode
      fields_txt_path = Path.join([src_path, "elements", "tiptap-AAC", "fields.txt"])
      assert File.exists?(fields_txt_path)

      element_json =
        Path.join([src_path, "elements", "tiptap-AAC", "AAC.json"])
        |> File.read!()
        |> Jason.decode!()

      assert Map.has_key?(element_json, "actions")
      assert Map.has_key?(element_json, "fields")
      refute Map.has_key?(element_json, "plugin_elements")

      # Check that the encoded JSON has the fields key
      assert Map.has_key?(dist_json, "plugin_elements")
      assert Map.has_key?(dist_json["plugin_elements"], "AAC")
      assert Map.has_key?(dist_json["plugin_elements"]["AAC"], "fields")

      element_fields = dist_json["plugin_elements"]["AAC"]["fields"]

      # Verify we have fields (should be many fields in the tiptap element)
      assert map_size(element_fields) > 0

      # Check that specific known fields exist (from the example plugin.json)
      assert Map.has_key?(element_fields, "AFz")
      assert element_fields["AFz"]["caption"] == "Allowed MIME Types"

      # Verify that fields have proper structure with rank, caption, etc.
      Enum.each(element_fields, fn {_key, field_data} ->
        assert is_map(field_data)
        assert Map.has_key?(field_data, "caption")
        assert Map.has_key?(field_data, "rank")
        assert is_binary(field_data["caption"])
        assert is_integer(field_data["rank"])
      end)

      # Test that fields.txt content matches some of the actual fields
      fields_txt_content = File.read!(fields_txt_path)
      assert fields_txt_content =~ "Allowed MIME Types (AFz)"
    end
  end
end
