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

    json =
      Path.wildcard(action_dir <> "/*.json")
      |> List.first()
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
      if File.exists?(server_js) do
        content = File.read!(server_js)
        existing_server = Map.get(original_code, "server", %{})

        UI.info("Using modified server function from server.js", verbose?)

        Map.put(
          base_properties,
          "server",
          Map.put(
            existing_server,
            "fn",
            wrapper(existing_server, "server") <> " {\n" <> content <> "\n}"
          )
        )
      else
        base_properties
      end

    updated_code =
      if File.exists?(client_js) do
        content = File.read!(client_js)
        existing_client = Map.get(original_code, "client", %{})

        UI.info("Using modified client function from client.js", verbose?)

        Map.put(
          updated_code,
          "client",
          Map.put(
            existing_client,
            "fn",
            wrapper(existing_client, "client") <> " {\n" <> content <> "\n}"
          )
        )
      else
        updated_code
      end

    %{"code" => updated_code}
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
