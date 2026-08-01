defmodule Pled.SyncCommandsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Pled.Commands.{CheckRemote, Decoder, Status}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    previous = %{
      plugin_id: System.get_env("PLUGIN_ID"),
      cookie: System.get_env("BUBBLE_COOKIE"),
      req_options: Application.get_env(:pled, :req_options),
      adapter_fun: Application.get_env(:pled, :test_adapter_fun),
      snapshot_file: Application.get_env(:pled, :src_snapshot_file),
      js_ast_runner: Application.get_env(:pled, :js_ast_runner)
    }

    System.put_env("PLUGIN_ID", "test-plugin")
    System.put_env("BUBBLE_COOKIE", "test-cookie")
    Application.put_env(:pled, :req_options, adapter: Pled.TestAdapter)
    Application.put_env(:pled, :src_snapshot_file, Path.join(tmp_dir, ".src.json"))

    Application.put_env(:pled, :js_ast_runner, fn source, _opts ->
      {:ok, %{"normalized" => String.replace(source, ~r/\s+/, "")}}
    end)

    on_exit(fn ->
      restore_system_env("PLUGIN_ID", previous.plugin_id)
      restore_system_env("BUBBLE_COOKIE", previous.cookie)
      restore_app_env(:req_options, previous.req_options)
      restore_app_env(:test_adapter_fun, previous.adapter_fun)
      restore_app_env(:src_snapshot_file, previous.snapshot_file)
      restore_app_env(:js_ast_runner, previous.js_ast_runner)
    end)

    base = read_fixture("small_plugin.json")
    write_workspace(tmp_dir, base)
    File.write!(Path.join(tmp_dir, ".src.json"), Jason.encode!(base))

    {:ok, base: base}
  end

  for {state, local_change, remote_change, expected_line, next_command} <- [
        {:in_sync, nil, nil, "In sync", "No action needed"},
        {:local_ahead, "Local name", nil, "Local ahead", "`pled push`"},
        {:remote_ahead, nil, "Remote name", "Remote ahead", "`pled pull`"},
        {
          :diverged,
          "Local name",
          "Remote name",
          "Diverged",
          "`pled pull --wipe`"
        },
        {:no_baseline, nil, nil, "No baseline", "`pled pull`"}
      ] do
    test "status and check-remote agree for #{state}", %{tmp_dir: tmp_dir, base: base} do
      apply_local_change(tmp_dir, unquote(local_change))

      if unquote(state) == :no_baseline do
        File.rm!(Path.join(tmp_dir, ".src.json"))
        test_process = self()

        Application.put_env(:pled, :js_ast_runner, fn _source, _opts ->
          send(test_process, :parsed_javascript)
          {:ok, %{}}
        end)
      end

      counter = stub_remote(remote_with_change(base, unquote(remote_change)))

      assert {status_output, :ok} = run_command(tmp_dir, Status, verbose: true)
      assert Agent.get(counter, & &1) == 1

      assert {check_remote_output, :ok} = run_command(tmp_dir, CheckRemote, verbose: true)
      assert Agent.get(counter, & &1) == 2

      for output <- [status_output, check_remote_output] do
        assert output =~ unquote(expected_line)
        assert output =~ unquote(next_command)
        refute output =~ "updating element"
      end

      assert sync_section(status_output) == String.trim(check_remote_output)
      refute File.exists?(Path.join(tmp_dir, "dist"))

      if unquote(state) == :no_baseline, do: refute_received(:parsed_javascript)

      if unquote(state) == :diverged do
        assert status_output =~ "`pled push --force`"
        assert check_remote_output =~ "`pled push --force`"
      end

      if unquote(state) in [:local_ahead, :remote_ahead, :diverged] do
        assert status_output =~ "Summary:"
        assert status_output =~ "Detailed changes:"
        assert check_remote_output =~ "Summary:"
        assert check_remote_output =~ "Detailed changes:"
        assert status_output =~ "1 × Metadata field changed"
        refute status_output =~ "Element field changed"
        refute status_output =~ "Action field changed"
      end
    end
  end

  test "default status and check-remote output agree", %{tmp_dir: tmp_dir, base: base} do
    apply_local_change(tmp_dir, "Local name")
    stub_remote(base)

    assert {status_output, :ok} = run_command(tmp_dir, Status)
    assert {check_remote_output, :ok} = run_command(tmp_dir, CheckRemote)

    assert sync_section(status_output) == String.trim(check_remote_output)
    refute status_output =~ "Detailed changes:"
  end

  test "malformed baseline errors name the snapshot and recovery command", %{
    tmp_dir: tmp_dir,
    base: base
  } do
    snapshot = Path.join(tmp_dir, ".src.json")
    File.write!(snapshot, "{not json")
    stub_remote(base)

    assert {output, {:error, reason}} = run_command(tmp_dir, CheckRemote)

    assert reason =~ "Invalid baseline snapshot JSON"
    assert output =~ "Invalid baseline snapshot JSON"
    assert output =~ snapshot
    assert output =~ "`pled pull`"
  end

  test "local build errors explain how to repair the source tree", %{tmp_dir: tmp_dir, base: base} do
    File.rm!(Path.join([tmp_dir, "src", "plugin.json"]))
    stub_remote(base)

    assert {output, {:error, reason}} = run_command(tmp_dir, CheckRemote)

    assert reason =~ "Failed to build local plugin"
    assert output =~ "Failed to build local plugin"
    assert output =~ "src/plugin.json"
    assert output =~ "`pled pull`"

    assert {status_output, {:error, ^reason}} = run_command(tmp_dir, Status)
    assert status_output =~ "Remote plugin is reachable"
    assert status_output =~ "Sync Status:"
    assert status_output =~ "Failed to build local plugin"
  end

  test "malformed local entity JSON is reported as an actionable build error", %{
    tmp_dir: tmp_dir,
    base: base
  } do
    [element_json | _] = Path.wildcard(Path.join([tmp_dir, "src", "elements", "*", "*.json"]))
    File.write!(element_json, "{not json")
    stub_remote(base)

    assert {output, {:error, reason}} = run_command(tmp_dir, CheckRemote)

    assert reason =~ "Failed to build local plugin"
    assert output =~ "Failed to build local plugin"
    assert output =~ "unexpected byte"
    assert output =~ "`pled pull`"
  end

  test "Bubble API errors retain the actionable API reason", %{tmp_dir: tmp_dir} do
    Application.put_env(:pled, :test_adapter_fun, fn request ->
      {request, %Req.Response{status: 400, body: %{"error" => "maintenance"}}}
    end)

    assert {output, {:error, {:remote_unreachable, reason} = error}} =
             run_command(tmp_dir, CheckRemote)

    assert reason =~ "Failed to fetch remote plugin"
    assert output =~ "Failed to fetch remote plugin"
    assert output =~ "HTTP 400"
    assert output =~ "maintenance"

    assert {status_output, {:error, ^error}} = run_command(tmp_dir, Status, verbose: true)
    assert status_output =~ "Could not fetch remote plugin"
    assert status_output =~ "HTTP 400"
    refute status_output =~ "Remote plugin is reachable"
  end

  test "validation issues from the local build are visible", %{tmp_dir: tmp_dir, base: base} do
    [fields_path | _] = Path.wildcard(Path.join([tmp_dir, "src", "elements", "*", "fields.txt"]))
    [first_line | rest] = fields_path |> File.read!() |> String.split("\n")
    [_caption, key] = Regex.run(~r/^.* \(([^)]+)\)$/, first_line)
    File.write!(fields_path, Enum.join(["Changed caption (#{key})" | rest], "\n"))
    stub_remote(base)

    assert {output, :ok} = run_command(tmp_dir, CheckRemote)
    assert output =~ "validation issue"
    assert output =~ "`pled encode`"
  end

  defp sync_section(status_output) do
    status_output
    |> String.split("Sync Status:\n", parts: 2)
    |> List.last()
    |> String.trim()
  end

  defp run_command(tmp_dir, command, opts \\ []) do
    caller = self()
    ref = make_ref()

    output =
      capture_io(fn ->
        result = File.cd!(tmp_dir, fn -> command.run(opts) end)
        send(caller, {ref, result})
      end)

    assert_receive {^ref, result}
    {output, result}
  end

  defp stub_remote(remote) do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    Application.put_env(:pled, :test_adapter_fun, fn request ->
      Agent.update(counter, &(&1 + 1))
      assert request.method == :get
      {request, %Req.Response{status: 200, body: remote}}
    end)

    counter
  end

  defp write_workspace(tmp_dir, plugin) do
    src_dir = Path.join(tmp_dir, "src")
    File.mkdir_p!(src_dir)
    File.write!(Path.join(src_dir, "plugin.json"), Jason.encode!(plugin, pretty: true))
    capture_io(fn -> assert :ok = Decoder.decode(plugin, tmp_dir) end)
  end

  defp apply_local_change(_tmp_dir, nil), do: :ok

  defp apply_local_change(tmp_dir, name) do
    path = Path.join([tmp_dir, "src", "plugin.json"])
    plugin = path |> File.read!() |> Jason.decode!() |> Map.put("name", name)
    File.write!(path, Jason.encode!(plugin, pretty: true))
  end

  defp remote_with_change(base, nil), do: base
  defp remote_with_change(base, name), do: Map.put(base, "name", name)

  defp read_fixture(name) do
    :code.priv_dir(:pled)
    |> to_string()
    |> Path.join("examples/#{name}")
    |> File.read!()
    |> Jason.decode!()
  end

  defp restore_system_env(name, nil), do: System.delete_env(name)
  defp restore_system_env(name, value), do: System.put_env(name, value)

  defp restore_app_env(key, nil), do: Application.delete_env(:pled, key)
  defp restore_app_env(key, value), do: Application.put_env(:pled, key, value)
end
