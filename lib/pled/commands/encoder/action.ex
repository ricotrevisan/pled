defmodule Pled.Commands.Encoder.Action do
  alias Pled.UI

  @default_wrappers %{
    "server" => "async function(properties, context)",
    "client" => "function(properties, context)"
  }

  def encode_actions(%{} = src_json, opts) do
    actions_dir = opts |> Keyword.get(:actions_dir)
    verbose? = Keyword.get(opts, :verbose, false)

    actions =
      if File.exists?(actions_dir) do
        actions_dir
        |> File.ls!()
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.reduce(
          %{},
          fn action_dir, acc ->
            {key, json} = encode_action(Path.join(actions_dir, action_dir), verbose?)
            Map.put(acc, key, json)
          end
        )
      else
        %{}
      end

    Map.put(src_json, "plugin_actions", actions)
  end

  def encode_action(action_dir, verbose?) do
    UI.info("encoding action #{action_dir}", verbose?)
    key = action_dir |> String.split("-") |> List.last()

    json_path =
      case Path.wildcard(action_dir <> "/*.json") do
        [path | _] ->
          path

        [] ->
          name = action_dir |> Path.basename() |> String.trim_trailing("-#{key}")

          raise File.Error,
            path: Path.join(action_dir, "#{name}.json"),
            reason: :enoent,
            action: "read"
      end

    json =
      json_path
      |> File.read!()
      |> Jason.decode!()

    code_block = generate_code_block(action_dir, json, verbose?)
    json = Map.merge(json, code_block)

    {key, json}
  end

  def generate_code_block(action_dir, original_json, verbose?) do
    # Get original functions from JSON if they exist
    original_code = Map.get(original_json, "code", %{})

    server_js =
      action_dir
      |> Path.join("server.js")

    client_js =
      action_dir
      |> Path.join("client.js")

    # Start with only the non-function properties from original code
    base_properties = Map.drop(original_code, ["server", "client"])

    updated_code =
      base_properties
      |> put_function(original_code, "server", server_js, verbose?)
      |> put_function(original_code, "client", client_js, verbose?)

    %{"code" => updated_code}
  end

  defp put_function(code, original_code, func, js_path, verbose?) do
    cond do
      File.exists?(js_path) ->
        content = File.read!(js_path)
        existing = Map.get(original_code, func, %{})

        UI.info("Using modified #{func} function from #{func}.js", verbose?)

        Map.put(
          code,
          func,
          Map.put(existing, "fn", wrapper(existing, func) <> " {\n" <> content <> "\n}")
        )

      Map.has_key?(original_code, func) ->
        # the action json has this code section, so its js file is expected;
        # dropping the code silently would delete it from the remote on push
        raise File.Error, path: js_path, reason: :enoent, action: "read"

      true ->
        code
    end
  end

  # The decoder preserves the original function signature in the action json
  # (async or not) so a rebuilt payload matches the remote byte-for-byte.
  # Older src trees lack it, so fall back to the historical defaults.
  defp wrapper(code_block, func) do
    case Pled.CodeBlock.signature(Map.get(code_block, "fn")) do
      {:ok, signature} -> signature
      :error -> @default_wrappers[func]
    end
  end
end
