defmodule Pled.Commands.Init do
  @moduledoc """
  Initialize a new Pled project structure.

  Usage:
    pled init <bubble-plugin-url-or-id>
    pled init https://bubble.io/plugin_editor?id=1234x5678
    pled init 1234x5678
  """

  alias Pled.PluginId

  def run(opts) do
    IO.puts("Initializing Pled project...")

    url_or_id = Keyword.get(opts, :url_or_id)

    with :ok <- save_plugin_id(url_or_id),
         :ok <- create_gitignore(),
         :ok <- create_agents_md(),
         :ok <- create_lib_directory(),
         :ok <- create_package_json(),
         :ok <- create_index_js(opts) do
      IO.puts("""

      ✓ Project initialized!

      Next steps:
      """)

      if System.get_env("COOKIE") == nil do
        IO.puts("1. Set COOKIE as a global env var (e.g. in ~/.zshrc)")
        IO.puts("2. Run 'pled pull' to fetch your plugin from Bubble.io")
      else
        IO.puts("1. Run 'pled pull' to fetch your plugin from Bubble.io")
      end

      if Keyword.get(opts, :react, false) do
        IO.puts("")

        IO.puts(
          "   Run `npm install react react-dom --prefix lib` to install the React libraries"
        )
      end

      :ok
    else
      error -> error
    end
  end

  defp save_plugin_id(nil) do
    # No argument provided — check if .plugin_id already exists
    case PluginId.load() do
      {:ok, id} ->
        IO.puts("⚠ Using existing plugin ID: #{id}")
        :ok

      {:error, _} ->
        IO.puts("""
        Usage: pled init <bubble-plugin-url-or-id>

        Examples:
          pled init https://bubble.io/plugin_editor?id=1234x5678
          pled init 1234x5678
        """)

        {:error, :missing_plugin_id}
    end
  end

  defp save_plugin_id(input) do
    case PluginId.extract(input) do
      {:ok, id} ->
        PluginId.save(id)
        IO.puts("✓ Saved plugin ID to .plugin_id: #{id}")
        :ok

      :error ->
        IO.puts("""
        ✗ Could not extract plugin ID from: #{input}

        Expected formats:
          https://bubble.io/plugin_editor?id=1234x5678
          1234x5678
        """)

        {:error, :invalid_plugin_id}
    end
  end

  defp create_agents_md do
    template_path = Application.app_dir(:pled, "priv/AGENTS.md.template")
    content = File.read!(template_path)

    case File.exists?("AGENTS.md") do
      true ->
        existing_content = File.read!("AGENTS.md")

        if String.contains?(existing_content, "# working with Pled") do
          IO.puts("⚠ AGENTS.md already contains Pled section, skipping...")
          :ok
        else
          File.write("AGENTS.md", existing_content <> content)
          IO.puts("✓ Updated AGENTS.md")
          :ok
        end

      false ->
        File.write("AGENTS.md", content)
        IO.puts("✓ Created AGENTS.md")
        :ok
    end
  end

  defp create_gitignore do
    entries = [".envrc", ".src.json", "lib/node_modules", "lib/dist*", "dist*"]
    gitignore_content = Enum.join(entries, "\n") <> "\n"

    case File.exists?(".gitignore") do
      true ->
        existing_content = File.read!(".gitignore")

        missing_entries =
          Enum.filter(entries, fn entry ->
            not String.contains?(existing_content, entry)
          end)

        if missing_entries == [] do
          IO.puts("⚠ .gitignore already contains all required entries, skipping...")
          :ok
        else
          new_content = existing_content <> "\n" <> Enum.join(missing_entries, "\n") <> "\n"
          File.write(".gitignore", new_content)

          IO.puts(
            "✓ Updated .gitignore with missing entries: #{Enum.join(missing_entries, ", ")}"
          )

          :ok
        end

      false ->
        File.write(".gitignore", gitignore_content)
        IO.puts("✓ Created .gitignore")
        :ok
    end
  end

  defp create_lib_directory do
    case File.mkdir_p("lib") do
      :ok ->
        IO.puts("✓ Created lib/ directory")
        :ok

      {:error, reason} ->
        IO.puts("✗ Failed to create lib/ directory: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp create_package_json do
    package_json_path = Path.join("lib", "package.json")

    case File.exists?(package_json_path) do
      true ->
        IO.puts("⚠ lib/package.json already exists, skipping...")
        update_existing_package_json(package_json_path)

      false ->
        package_json = """
        {
          "name": "my-plugin-package",
          "version": "0.0.1",
          "description": "",
          "main": "index.js",
          "scripts": {
              "build": "esbuild index.js --bundle --minify --outfile=dist.js"
          },
          "keywords": [],
          "author": "",
          "license": "ISC"
        }

        """

        File.write(package_json_path, package_json)
    end
  end

  defp update_existing_package_json(package_json_path) do
    case File.read(package_json_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, json} ->
            scripts = Map.get(json, "scripts", %{})

            updated_scripts =
              Map.put(scripts, "build", "esbuild index.js --bundle --minify --outfile=dist.js")

            updated_json = Map.put(json, "scripts", updated_scripts)

            case Jason.encode(updated_json, pretty: true) do
              {:ok, updated_content} ->
                File.write(package_json_path, updated_content)
                IO.puts("✓ Added build script to lib/package.json")
                :ok

              {:error, reason} ->
                IO.puts("✗ Failed to encode JSON: #{inspect(reason)}")
                {:error, reason}
            end

          {:error, reason} ->
            IO.puts("✗ Failed to parse package.json: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        IO.puts("✗ Failed to read package.json: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp create_index_js(opts) do
    index_js_path = Path.join("lib", "index.js")

    case File.exists?(index_js_path) do
      true ->
        IO.puts("⚠ lib/index.js already exists, skipping...")
        :ok

      false ->
        content =
          case Keyword.get(opts, :react, false) do
            true -> index_js_content(:react)
            false -> index_js_content()
          end

        File.write(index_js_path, content)
        IO.puts("✓ Created lib/index.js")
        :ok
    end
  end

  defp index_js_content(:react) do
    """
    import { createElement } from "react";
    import ReactDOM from "react-dom";
    import { createRoot } from "react-dom/client";

    // create a object to store those modules, for example
    // window.MyPluginModules = { createElement, ReactDOM, createRoot };

    """
  end

  defp index_js_content do
    """
    """
  end
end
