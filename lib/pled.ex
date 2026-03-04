defmodule Pled do
  @moduledoc """
  Pled - Bubble.io Plugin Development Tool
  """
  alias Pled.Commands

  @spec main([String.t()]) :: no_return()
  def main(args) do
    case args
         |> parse_args()
         |> handle_command() do
      :ok ->
        System.halt(0)

      {:error, reason} ->
        IO.puts("Command failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  def parse_args(args) do
    case args do
      ["pull" | rest] ->
        {parsed, remaining, invalid} =
          OptionParser.parse(rest,
            strict: [wipe: :boolean, help: :boolean, verbose: :boolean],
            aliases: [w: :wipe, h: :help, v: :verbose]
          )

        if invalid != [] or remaining != [], do: {:help, []}, else: {:pull, parsed}

      ["push" | rest] ->
        {parsed, remaining, invalid} =
          OptionParser.parse(rest,
            strict: [help: :boolean, verbose: :boolean, force: :boolean],
            aliases: [h: :help, v: :verbose, f: :force]
          )

        if invalid != [] or remaining != [], do: {:help, []}, else: {:push, parsed}

      ["encode" | rest] ->
        {parsed, remaining, invalid} =
          OptionParser.parse(rest,
            strict: [help: :boolean, verbose: :boolean],
            aliases: [h: :help, v: :verbose]
          )

        if invalid != [] or remaining != [], do: {:help, []}, else: {:encode, parsed}

      ["upload", file_path | rest] ->
        {parsed, remaining, invalid} =
          OptionParser.parse(rest,
            strict: [help: :boolean, verbose: :boolean],
            aliases: [h: :help, v: :verbose]
          )

        if invalid != [] or remaining != [], do: {:help, []}, else: {:upload, {file_path, parsed}}

      ["watch" | rest] ->
        {parsed, remaining, invalid} =
          OptionParser.parse(rest,
            strict: [help: :boolean, verbose: :boolean],
            aliases: [h: :help, v: :verbose]
          )

        if invalid != [] or remaining != [], do: {:help, []}, else: {:watch, parsed}

      ["init" | rest] ->
        {parsed, remaining, invalid} =
          OptionParser.parse(rest,
            strict: [help: :boolean, verbose: :boolean, react: :boolean],
            aliases: [h: :help, v: :verbose, r: :react]
          )

        if invalid != [] do
          {:help, []}
        else
          # First positional arg is the URL or plugin ID
          opts =
            case remaining do
              [url_or_id | _] -> Keyword.put(parsed, :url_or_id, url_or_id)
              [] -> parsed
            end

          {:init, opts}
        end

      ["check-remote" | rest] ->
        {parsed, remaining, invalid} =
          OptionParser.parse(rest,
            strict: [help: :boolean, verbose: :boolean],
            aliases: [h: :help, v: :verbose]
          )

        if invalid != [] or remaining != [], do: {:help, []}, else: {:check_remote, parsed}

      ["status" | rest] ->
        {parsed, remaining, invalid} =
          OptionParser.parse(rest,
            strict: [help: :boolean, verbose: :boolean],
            aliases: [h: :help, v: :verbose]
          )

        if invalid != [] or remaining != [], do: {:help, []}, else: {:status, parsed}

      [] ->
        {:help, []}

      _ ->
        {:help, []}
    end
  end

  def handle_command({:encode, opts}), do: Commands.Encoder.encode(opts)
  def handle_command({:pull, opts}), do: Commands.Pull.run(opts)
  def handle_command({:push, opts}), do: Commands.Push.run(opts)
  def handle_command({:upload, {file_path, opts}}), do: Commands.Upload.run(file_path, opts)
  def handle_command({:watch, opts}), do: Commands.Watch.run(opts)
  def handle_command({:init, opts}), do: Commands.Init.run(opts)
  def handle_command({:check_remote, opts}), do: Commands.CheckRemote.run(opts)
  def handle_command({:status, opts}), do: Commands.Status.run(opts)
  def handle_command({:help, _opts}), do: Commands.Help.run()
end
