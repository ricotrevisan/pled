defmodule Pled.EncoderTest do
  use ExUnit.Case, async: true

  alias Pled.Commands.Encoder

  describe "encode actions" do
    @describetag :tmp_dir
    setup %{tmp_dir: tmp_dir} do
      priv_dir = :code.priv_dir(:pled) |> to_string()

      plugin_data =
        File.read!(Path.join([priv_dir, "examples/small_plugin.json"]))
        |> Jason.decode!()

      Pled.Commands.Decoder.decode(plugin_data, tmp_dir)

      src_dir = "src"
      dist_dir = "dist"
      File.mkdir_p(dist_dir)

      opts = [
        src_dir: src_dir,
        dist_dir: dist_dir,
        elements_dir: Path.join(src_dir, "elements"),
        actions_dir: Path.join(src_dir, "actions")
      ]

      {:ok, src_json: plugin_data, opts: opts}
    end
  end

  describe "encode elements" do
    @describetag :tmp_dir
    setup %{tmp_dir: tmp_dir} do
      priv_dir = :code.priv_dir(:pled) |> to_string()

      # Create a properly named element directory (convention: display-name-KEY)
      element_dir = Path.join(tmp_dir, "test-element-AAC")
      File.mkdir_p!(element_dir)

      File.cp(
        Path.join([priv_dir, "examples/single_element.json"]),
        Path.join(element_dir, "AAC.json")
      )

      File.write(Path.join(element_dir, ".key"), "AAC")

      File.write(element_dir |> Path.join("initialize.js"), "console.log('this is a test')")
      File.write(element_dir |> Path.join("update.js"), "console.log('this is a test')")
      File.write(element_dir |> Path.join("reset.js"), "console.log('this is a test')")
      File.write(element_dir |> Path.join("preview.js"), "console.log('this is a test')")

      {:ok, %{element_dir: element_dir}}
    end

    test "encode_element/1", %{element_dir: element_dir} do
      encoded_element = Encoder.Element.encode_element(element_dir)
      assert is_tuple(encoded_element)
      {:ok, {key, value}, []} = encoded_element
      assert key == "AAC"
      assert is_map(value["code"])
      assert Map.keys(value["code"]["initialize"])
    end

    test "generate_code_block/1", %{element_dir: element_dir} do
      generated_code = Encoder.Element.generate_code_block(element_dir)
      assert is_map(generated_code)
      assert Map.keys(generated_code) == ["code"]
      assert Map.keys(generated_code["code"]) == ["initialize", "preview", "reset", "update"]
    end

    test "generate_js_file/2 :initialize", %{element_dir: element_dir} do
      generated_map = Encoder.Element.generate_js_file(:initialize, element_dir)
      assert is_map(generated_map)
      assert Map.keys(generated_map) == ["initialize"]
      assert Map.keys(generated_map["initialize"]) == ["fn"]

      generated_fn = generated_map["initialize"]["fn"]
      assert String.starts_with?(generated_fn, "function(instance, context) {\n")
      assert String.ends_with?(generated_fn, "\n}")
    end

    test "generate_js_file/2 :update", %{element_dir: element_dir} do
      generated_map = Encoder.Element.generate_js_file(:update, element_dir)
      assert is_map(generated_map)
      assert Map.keys(generated_map) == ["update"]
      assert Map.keys(generated_map["update"]) == ["fn"]

      generated_fn = generated_map["update"]["fn"]
      assert String.starts_with?(generated_fn, "function(instance, properties, context) {\n")
      assert String.ends_with?(generated_fn, "\n}")
    end

    test "generate_js_file/2 :reset", %{element_dir: element_dir} do
      generated_map = Encoder.Element.generate_js_file(:reset, element_dir)
      assert is_map(generated_map)
      assert Map.keys(generated_map) == ["reset"]
      assert Map.keys(generated_map["reset"]) == ["fn"]

      generated_fn = generated_map["reset"]["fn"]
      assert String.starts_with?(generated_fn, "function(instance, context) {\n")
      assert String.ends_with?(generated_fn, "\n}")
    end

    test "generate_js_file/2 :preview", %{element_dir: element_dir} do
      generated_map = Encoder.Element.generate_js_file(:preview, element_dir)
      assert is_map(generated_map)
      assert Map.keys(generated_map) == ["preview"]
      assert Map.keys(generated_map["preview"]) == ["fn"]

      generated_fn = generated_map["preview"]["fn"]
      assert String.starts_with?(generated_fn, "function(instance, properties) {\n")
      assert String.ends_with?(generated_fn, "\n}")
    end

    test "unchanged field order keeps the original ranks", %{element_dir: element_dir} do
      fields_content = """
      Header font color (ADe)
      Allowed MIME Types (AFz)
      """

      File.write!(Path.join(element_dir, "fields.txt"), fields_content)

      {:ok, {_key, result}, []} = Encoder.Element.encode_element(element_dir)

      fields = result["fields"]
      assert fields["ADe"]["rank"] == 56
      assert fields["AFz"]["rank"] == 101

      # Captions should remain unchanged
      assert fields["ADe"]["caption"] == "Header font color"
      assert fields["AFz"]["caption"] == "Allowed MIME Types"
    end

    test "field reordering reassigns the original rank values", %{element_dir: element_dir} do
      fields_content = """
      Allowed MIME Types (AFz)
      Header font color (ADe)
      """

      File.write!(Path.join(element_dir, "fields.txt"), fields_content)

      {:ok, {_key, result}, []} = Encoder.Element.encode_element(element_dir)

      fields = result["fields"]
      assert fields["AFz"]["rank"] == 56
      assert fields["ADe"]["rank"] == 101
    end

    test "field caption changes are applied and surfaced as issues", %{element_dir: element_dir} do
      fields_content = """
      Modified Header Color (ADe)
      Custom MIME Types (AFz)
      """

      File.write!(Path.join(element_dir, "fields.txt"), fields_content)

      {:ok, {_key, encoded}, issues} = Encoder.Element.encode_element(element_dir)

      fields = encoded["fields"]
      assert fields["ADe"]["caption"] == "Modified Header Color"
      assert fields["AFz"]["caption"] == "Custom MIME Types"

      assert Enum.sort_by(issues, & &1.field) == [
               %{
                 type: :field_caption_change,
                 element: "AAC",
                 field: "ADe",
                 from: "Header font color",
                 to: "Modified Header Color"
               },
               %{
                 type: :field_caption_change,
                 element: "AAC",
                 field: "AFz",
                 from: "Allowed MIME Types",
                 to: "Custom MIME Types"
               }
             ]
    end

    test "field validation - duplicate keys", %{element_dir: element_dir} do
      fields_content = """
      Header font color (ADe)
      Duplicate field (ADe)
      """

      File.write!(Path.join(element_dir, "fields.txt"), fields_content)

      assert {:error, error_msg} = Encoder.Element.encode_element(element_dir)
      assert error_msg =~ "Duplicate keys found"
      assert error_msg =~ "ADe (appears 2 times)"
    end

    test "field validation - malformed lines", %{element_dir: element_dir} do
      fields_content = """
      Header font color (ADe)
      This line is malformed
      """

      File.write!(Path.join(element_dir, "fields.txt"), fields_content)

      assert {:error, error_msg} = Encoder.Element.encode_element(element_dir)
      assert error_msg =~ "Field parsing failed"
      assert error_msg =~ "Malformed line: This line is malformed"
    end
  end

  describe "encode root" do
    @describetag :tmp_dir
    setup %{tmp_dir: tmp_dir} do
      priv_dir = :code.priv_dir(:pled) |> to_string()

      plugin_data =
        File.read!(Path.join([priv_dir, "examples/plugin.json"])) |> Jason.decode!()

      # Decoder.decode expects src/plugin.json to exist for clean_plugin_data
      src_dir = Path.join(tmp_dir, "src")
      File.mkdir_p!(src_dir)
      File.write!(Path.join(src_dir, "plugin.json"), Jason.encode!(plugin_data, pretty: true))

      Pled.Commands.Decoder.decode(plugin_data, tmp_dir)

      src_dir = Path.join(tmp_dir, "src")
      dist_dir = Path.join(tmp_dir, "dist")
      File.mkdir_p(dist_dir)

      opts = [
        src_dir: src_dir,
        dist_dir: dist_dir,
        elements_dir: Path.join(src_dir, "elements"),
        actions_dir: Path.join(src_dir, "actions")
      ]

      {:ok, src_json: plugin_data, opts: opts}
    end

    test "html snippet", %{src_json: src_json, opts: opts} do
      updated_json = Encoder.encode_html(src_json, opts)

      assert Map.has_key?(updated_json, "html_header")
      assert Map.has_key?(updated_json["html_header"], "snippet")
      assert get_in(updated_json, ["html_header", "snippet"]) =~ "script"
    end
  end
end
