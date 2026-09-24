defmodule Pled.DecoderTest do
  use ExUnit.Case, async: true

  alias Pled.Commands.Decoder

  describe "decoder" do
    @describetag :tmp_dir
    setup %{tmp_dir: tmp_dir} do
      priv_dir = :code.priv_dir(:pled) |> to_string()

      plugin_data =
        File.read!(Path.join(priv_dir, "examples/small_plugin.json")) |> Jason.decode!()

      src_dir = Path.join(tmp_dir, "src")
      File.mkdir(src_dir)

      {:ok, plugin_data: plugin_data}
    end

    test "html_header", %{plugin_data: plugin_data, tmp_dir: tmp_dir} do
      plugin_data
      |> Decoder.decode_html_header(tmp_dir)

      ls =
        tmp_dir
        |> Path.join("src")
        |> File.ls!()

      assert "shared.html" in ls

      html_file = Path.join(tmp_dir, "src/shared.html")
      assert File.exists?(html_file)

      snippet = File.read!(html_file)
      assert snippet =~ "script"
    end

    test "remove_bubbleisms/1 strips only the outer wrapper" do
      string =
        """
        function(instance, properties, context) {

          //Load any data
          //Do the operation

        }
        """

      refute Decoder.remove_bubbleisms(string) =~ "function"
    end

    test "preserves nested function assignments and async code" do
      body = """
      data.disable = function(disable) {
        publish('is_disabled', disable);
      };
      data.addQueryParam = function(url, param, value) {
        return `${url}?${param}=${value}`;
      };
      """

      assert Decoder.remove_bubbleisms("function(instance, context) {\n#{body}}") ==
               String.trim(body)

      assert Decoder.remove_bubbleisms("async function(properties, context) {\n#{body}}") ==
               String.trim(body)
    end

    test "rejects a missing wrapper rather than mangling source" do
      assert_raise ArgumentError, ~r/not a complete function wrapper/, fn ->
        Decoder.remove_bubbleisms("data.disable = function(disable) { return disable; };")
      end
    end
  end

  describe "key-slug combination functionality" do
    @describetag :tmp_dir
    setup %{tmp_dir: tmp_dir} do
      src_dir = Path.join(tmp_dir, "src")
      File.mkdir(src_dir)
      {:ok, []}
    end

    test "elements with same display name get unique directories", %{tmp_dir: tmp_dir} do
      plugin_data = %{
        "plugin_elements" => %{
          "key1" => %{"display" => "Same Name", "code" => %{}},
          "key2" => %{"display" => "Same Name", "code" => %{}}
        }
      }

      Decoder.decode_elements(plugin_data, tmp_dir)

      elements_dir = Path.join(tmp_dir, "src/elements")
      dirs = File.ls!(elements_dir)

      assert "same-name-key1" in dirs
      assert "same-name-key2" in dirs
      assert length(dirs) == 2
    end

    test "actions with same display name get unique directories", %{tmp_dir: tmp_dir} do
      plugin_data = %{
        "plugin_actions" => %{
          "key1" => %{"display" => "Same Action", "code" => %{}},
          "key2" => %{"display" => "Same Action", "code" => %{}}
        }
      }

      Decoder.decode_actions(plugin_data, tmp_dir)

      actions_dir = Path.join(tmp_dir, "src/actions")
      dirs = File.ls!(actions_dir)

      assert "same-action-key1" in dirs
      assert "same-action-key2" in dirs
      assert length(dirs) == 2
    end

    test "element actions hybrid approach: JSON + JS files", %{tmp_dir: tmp_dir} do
      plugin_data = %{
        "plugin_elements" => %{
          "element_key" => %{
            "display" => "Test Element",
            "code" => %{},
            "actions" => %{
              "action_key1" => %{
                "caption" => "Same Action",
                "code" => %{
                  "fn" => "function(instance, properties, context) {\nconsole.log('1');\n}"
                }
              },
              "action_key2" => %{
                "caption" => "Same Action",
                "code" => %{
                  "fn" => "function(instance, properties, context) {\nconsole.log('2');\n}"
                }
              }
            }
          }
        }
      }

      Decoder.decode_elements(plugin_data, tmp_dir)

      element_dir = Path.join(tmp_dir, "src/elements/test-element-element_key")
      actions_dir = Path.join(element_dir, "actions")

      # Actions directory should exist with JS files
      assert File.exists?(actions_dir)

      # Check for JS files
      files = File.ls!(actions_dir)
      assert "same-action-action_key1.js" in files
      assert "same-action-action_key2.js" in files
      # Only JS files, no JSON or key files
      assert length(files) == 2

      # Verify JS files contain cleaned JavaScript (without function wrapper)
      js_content1 = File.read!(Path.join(actions_dir, "same-action-action_key1.js"))
      assert String.trim(js_content1) == "console.log('1');"

      js_content2 = File.read!(Path.join(actions_dir, "same-action-action_key2.js"))
      assert String.trim(js_content2) == "console.log('2');"

      # Actions should also be preserved in the element JSON
      element_json_path = Path.join(element_dir, "element_key.json")
      assert File.exists?(element_json_path)

      element_data = element_json_path |> File.read!() |> Jason.decode!()
      assert Map.has_key?(element_data, "actions")
      assert map_size(element_data["actions"]) == 2
      assert Map.has_key?(element_data["actions"], "action_key1")
      assert Map.has_key?(element_data["actions"], "action_key2")
    end
  end
end
