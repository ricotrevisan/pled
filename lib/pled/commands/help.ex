defmodule Pled.Commands.Help do
  def run do
    logo()

    IO.puts("""

    Bubble.io Plugin Development Tool
    version #{Application.get_env(:pled, :version)}

    Usage:
      pled init <url|id>    Initialize project with a Bubble plugin URL or ID
      pled pull             Fetch plugin from Bubble.io and save to src/plugin.json
      pled pull --wipe      Discard local changes and pull
      pled push             Encodes and then upload plugin to Bubble.io
      pled push --force     Force push, overwriting remote changes
      pled encode           Prepares the files to upload. Compiles src/ files into dist/plugin.json
      pled upload <file>    Upload a file to Bubble.io CDN
      pled watch            Watches the `src/` directory for changes and pushes to Bubble
      pled check-remote     Check for remote changes without pushing
      pled status           Show environment, auth, and sync status

    Configuration:
      .plugin_id            Plugin ID (created by 'pled init', committed to repo)
      BUBBLE_COOKIE env var Authentication cookie for Bubble.io (the only secret)

    Run 'pled help <command>' for detailed help on a specific command.
    """)

    :ok
  end

  def logo do
    IO.puts(~S(
        __________________________________________________________
       ___/\/\/\/\/\____/\/\________/\/\/\/\/\/\__/\/\/\/\/\_____
      ___/\/\____/\/\__/\/\________/\____________/\/\____/\/\___
     ___/\/\/\/\/\____/\/\________/\/\/\/\/\____/\/\____/\/\___
    ___/\/\__________/\/\________/\/\__________/\/\____/\/\___
   ___/\/\__________/\/\/\/\/\__/\/\/\/\/\/\__/\/\/\/\/\_____
  __________________________________________________________
        ))
  end
end
