defmodule Pled.Commands.Encoder.ActionTest do
  use ExUnit.Case, async: true

  alias Pled.Commands.Encoder.Action

  describe "encode_actions/2" do
    @describetag :tmp_dir
    setup %{tmp_dir: tmp_dir} do
      # Create actions directory structure
      actions_dir = Path.join(tmp_dir, "actions")
      File.mkdir_p!(actions_dir)

      # Create a sample action (directory name must end with -KEY)
      action_dir = Path.join(actions_dir, "sample-action-ABC")
      File.mkdir_p!(action_dir)

      # Write action JSON with additional properties to test preservation
      action_json = %{
        "caption" => "Sample Action",
        "code" => %{
          "automatically_added_packages" =>
            "{\"jsonwebtoken\":\"latest\",\"node:util\":\"latest\"}",
          "package" => %{
            "fn" => "{\n    \"dependencies\": {\n        \"jsonwebtoken\": \"latest\"\n    }\n}",
            "invalid_package" => false
          },
          "package_hash" => "1e76bc4a16a53766f915",
          "package_status" => "out_of_date",
          "package_used" => true,
          "server" => %{
            "fn" =>
              "async function(properties, context) {\n    console.log('original server code');\n    return { message: 'hello' };\n}"
          },
          "client" => %{
            "fn" => "function(properties, context) {\n    console.log('original client code');\n}"
          }
        }
      }

      File.write!(Path.join(action_dir, "ABC.json"), Jason.encode!(action_json))

      # Write JS files with original content (extracted from the functions)
      File.write!(
        Path.join(action_dir, "server.js"),
        "    console.log('original server code');\n    return { message: 'hello' };"
      )

      File.write!(Path.join(action_dir, "client.js"), "    console.log('original client code');")

      src_json = %{"plugin_actions" => %{}}
      opts = [actions_dir: actions_dir]

      {:ok, src_json: src_json, opts: opts, action_dir: action_dir, action_json: action_json}
    end

    test "uses original function when JS files are unchanged", %{
      src_json: src_json,
      opts: opts,
      action_json: action_json
    } do
      import ExUnit.CaptureIO

      capture_io(fn ->
        result = Action.encode_actions(src_json, opts)
        send(self(), {:result, result})
      end)

      assert_received {:result, result}

      # Verify the exact original functions are preserved
      encoded_action = result["plugin_actions"]["ABC"]
      assert encoded_action["code"]["server"]["fn"] == action_json["code"]["server"]["fn"]
      assert encoded_action["code"]["client"]["fn"] == action_json["code"]["client"]["fn"]

      # Verify all other code properties are preserved
      assert encoded_action["code"]["automatically_added_packages"] ==
               action_json["code"]["automatically_added_packages"]

      assert encoded_action["code"]["package"] == action_json["code"]["package"]
      assert encoded_action["code"]["package_hash"] == action_json["code"]["package_hash"]
      assert encoded_action["code"]["package_status"] == action_json["code"]["package_status"]
      assert encoded_action["code"]["package_used"] == action_json["code"]["package_used"]
    end

    test "uses modified function when server.js is changed", %{
      src_json: src_json,
      opts: opts,
      action_dir: action_dir,
      action_json: action_json
    } do
      import ExUnit.CaptureIO

      # Modify server.js
      File.write!(
        Path.join(action_dir, "server.js"),
        "    console.log('modified server code');\n    return { message: 'modified' };"
      )

      capture_io(fn ->
        result = Action.encode_actions(src_json, opts)
        send(self(), {:result, result})
      end)

      assert_received {:result, result}

      # Verify the server function was updated but other properties preserved
      encoded_action = result["plugin_actions"]["ABC"]
      server_fn = encoded_action["code"]["server"]["fn"]
      assert server_fn =~ "modified server code"
      assert server_fn =~ "async function(properties, context)"

      # Verify all other code properties are still preserved
      assert encoded_action["code"]["automatically_added_packages"] ==
               action_json["code"]["automatically_added_packages"]

      assert encoded_action["code"]["package"] == action_json["code"]["package"]
      assert encoded_action["code"]["package_hash"] == action_json["code"]["package_hash"]
    end

    test "uses modified function when client.js is changed", %{
      src_json: src_json,
      opts: opts,
      action_dir: action_dir,
      action_json: action_json
    } do
      import ExUnit.CaptureIO

      # Modify client.js
      File.write!(
        Path.join(action_dir, "client.js"),
        "    console.log('modified client code');\n    alert('hello');"
      )

      capture_io(fn ->
        result = Action.encode_actions(src_json, opts)
        send(self(), {:result, result})
      end)

      assert_received {:result, result}

      # Verify only client function was updated, everything else preserved
      encoded_action = result["plugin_actions"]["ABC"]
      assert encoded_action["code"]["server"]["fn"] == action_json["code"]["server"]["fn"]

      client_fn = encoded_action["code"]["client"]["fn"]
      assert client_fn =~ "modified client code"
      assert client_fn =~ "function(properties, context)"

      # Verify all other code properties are still preserved
      assert encoded_action["code"]["automatically_added_packages"] ==
               action_json["code"]["automatically_added_packages"]

      assert encoded_action["code"]["package"] == action_json["code"]["package"]
      assert encoded_action["code"]["package_hash"] == action_json["code"]["package_hash"]
    end

    test "handles missing JS files", %{
      src_json: src_json,
      opts: opts,
      action_dir: action_dir,
      action_json: action_json
    } do
      import ExUnit.CaptureIO

      # Delete JS files
      File.rm!(Path.join(action_dir, "server.js"))
      File.rm!(Path.join(action_dir, "client.js"))

      _output =
        capture_io(fn ->
          result = Action.encode_actions(src_json, opts)
          send(self(), {:result, result})
        end)

      assert_received {:result, result}

      # Should preserve non-function properties when JS files are missing
      encoded_action = result["plugin_actions"]["ABC"]

      # Should not have server or client functions, but preserve other properties
      assert Map.has_key?(encoded_action["code"], "server") == false
      assert Map.has_key?(encoded_action["code"], "client") == false

      # Should preserve all other properties
      assert encoded_action["code"]["automatically_added_packages"] ==
               action_json["code"]["automatically_added_packages"]

      assert encoded_action["code"]["package"] == action_json["code"]["package"]
      assert encoded_action["code"]["package_hash"] == action_json["code"]["package_hash"]
      assert encoded_action["code"]["package_status"] == action_json["code"]["package_status"]
      assert encoded_action["code"]["package_used"] == action_json["code"]["package_used"]
    end

    test "handles actions without original code", %{
      src_json: src_json,
      action_dir: action_dir
    } do
      import ExUnit.CaptureIO

      # Create action JSON without code block
      action_json_no_code = %{
        "caption" => "Sample Action"
      }

      File.write!(Path.join(action_dir, "ABC.json"), Jason.encode!(action_json_no_code))

      # Use verbose: true so UI.info messages are printed
      verbose_opts = [actions_dir: Path.dirname(action_dir), verbose: true]

      output =
        capture_io(fn ->
          result = Action.encode_actions(src_json, verbose_opts)
          send(self(), {:result, result})
        end)

      assert_received {:result, result}

      # Should create new functions from JS files
      assert output =~ "Using modified server function from server.js"
      assert output =~ "Using modified client function from client.js"

      encoded_action = result["plugin_actions"]["ABC"]
      assert encoded_action["code"]["server"]["fn"] =~ "async function(properties, context)"
      assert encoded_action["code"]["client"]["fn"] =~ "function(properties, context)"
    end

    test "encodes multiple actions", %{tmp_dir: tmp_dir} do
      import ExUnit.CaptureIO

      # Create a fresh actions directory for this test
      actions_dir = Path.join(tmp_dir, "multi_actions")
      File.mkdir_p!(actions_dir)

      # Create multiple actions (directory name must end with -KEY)
      for {key, name} <- [{"ABC", "Action One"}, {"DEF", "Action Two"}] do
        action_dir =
          Path.join(actions_dir, "#{String.downcase(name) |> String.replace(" ", "-")}-#{key}")

        File.mkdir_p!(action_dir)

        action_json = %{
          "caption" => name,
          "code" => %{
            "server" => %{
              "fn" => "async function(properties, context) {\n    // #{name} server\n}"
            }
          }
        }

        File.write!(Path.join(action_dir, "#{key}.json"), Jason.encode!(action_json))
        File.write!(Path.join(action_dir, "server.js"), "    // #{name} server")
      end

      src_json = %{"plugin_actions" => %{}}
      opts = [actions_dir: actions_dir]

      capture_io(fn ->
        result = Action.encode_actions(src_json, opts)
        send(self(), {:result, result})
      end)

      assert_received {:result, result}

      # Should have both actions
      assert Map.keys(result["plugin_actions"]) |> Enum.sort() == ["ABC", "DEF"]
    end
  end

  describe "generate_code_block/2" do
    @describetag :tmp_dir
    setup %{tmp_dir: tmp_dir} do
      original_json = %{
        "code" => %{
          "server" => %{
            "fn" => "async function(properties, context) {\n    return { original: true };\n}"
          },
          "client" => %{
            "fn" => "function(properties, context) {\n    console.log('original');\n}"
          }
        }
      }

      {:ok, action_dir: tmp_dir, original_json: original_json}
    end

    test "returns empty map when no JS files exist", %{
      action_dir: action_dir,
      original_json: original_json
    } do
      result = Action.generate_code_block(action_dir, original_json, false)
      # Should preserve non-function properties but remove server/client functions
      expected_code = original_json["code"] |> Map.drop(["server", "client"])
      assert result == %{"code" => expected_code}
    end

    test "generates server function only", %{action_dir: action_dir, original_json: original_json} do
      File.write!(Path.join(action_dir, "server.js"), "    return { modified: true };")

      result = Action.generate_code_block(action_dir, original_json, false)

      assert Map.keys(result["code"]) == ["server"]
      assert result["code"]["server"]["fn"] =~ "modified: true"
    end

    test "generates client function only", %{action_dir: action_dir, original_json: original_json} do
      File.write!(Path.join(action_dir, "client.js"), "    console.log('modified');")

      result = Action.generate_code_block(action_dir, original_json, false)

      assert Map.keys(result["code"]) == ["client"]
      assert result["code"]["client"]["fn"] =~ "modified"
    end

    test "preserves original when no code section exists", %{action_dir: action_dir} do
      File.write!(Path.join(action_dir, "server.js"), "    return { new: true };")

      # Pass JSON without code section
      result = Action.generate_code_block(action_dir, %{}, false)

      # Should still generate new function
      assert result["code"]["server"]["fn"] =~ "new: true"
    end
  end
end
