defmodule Pled.Commands.PullTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Pled.Commands.{Decoder, Encoder, Pull, Push, Status}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    previous = %{
      plugin_id: System.get_env("PLUGIN_ID"),
      cookie: System.get_env("BUBBLE_COOKIE"),
      req_options: Application.get_env(:pled, :req_options),
      adapter_fun: Application.get_env(:pled, :test_adapter_fun),
      snapshot_file: Application.get_env(:pled, :src_snapshot_file),
      js_ast_runner: Application.get_env(:pled, :js_ast_runner),
      interactive: Application.get_env(:pled, :interactive)
    }

    System.put_env("PLUGIN_ID", "test-plugin")
    System.put_env("BUBBLE_COOKIE", "test-cookie")
    Application.put_env(:pled, :req_options, adapter: Pled.TestAdapter)
    Application.put_env(:pled, :src_snapshot_file, Path.join(tmp_dir, ".src.json"))
    Application.put_env(:pled, :interactive, false)

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
      restore_app_env(:interactive, previous.interactive)
    end)

    base = read_fixture("small_plugin.json")
    write_workspace(tmp_dir, base)
    File.write!(Path.join(tmp_dir, ".src.json"), Jason.encode!(base))
    remote = stub_remote(base)

    {:ok, base: base, remote: remote}
  end

  test "local-ahead is refused and leaves local files untouched", %{tmp_dir: tmp_dir} do
    change_local_name(tmp_dir, "Local name")

    assert {output, {:error, :local_ahead}} = run_pull(tmp_dir)

    assert output =~ "Pull refused"
    assert output =~ "`pled pull --wipe`"
    assert local_name(tmp_dir) == "Local name"
  end

  test "CLI marks pull refusals as already reported", %{tmp_dir: tmp_dir} do
    change_local_name(tmp_dir, "Local name")

    assert {output, {:error, {:reported, :local_ahead}}} =
             run_captured(tmp_dir, fn -> Pled.handle_command({:pull, []}) end, nil)

    assert output =~ "Pull refused"
    refute output =~ "Pull failed"
  end

  test "diverged is refused with both resolution options", %{
    tmp_dir: tmp_dir,
    base: base,
    remote: remote
  } do
    change_local_name(tmp_dir, "Local name")
    set_remote(remote, Map.put(base, "name", "Remote name"))

    assert {output, {:error, :diverged}} = run_pull(tmp_dir)

    assert output =~ "Pull refused"
    assert output =~ "`pled pull --wipe`"
    assert local_name(tmp_dir) == "Local name"
  end

  test "--wipe discards local changes and pulls the remote", %{
    tmp_dir: tmp_dir,
    base: base,
    remote: remote
  } do
    change_local_name(tmp_dir, "Local name")
    set_remote(remote, Map.put(base, "name", "Remote name"))

    assert {output, :ok} = run_pull(tmp_dir, wipe: true)

    assert output =~ "Pull completed"
    assert local_name(tmp_dir) == "Remote name"
  end

  test "remote-ahead pulls cleanly and the next status reports in sync", %{
    tmp_dir: tmp_dir,
    base: base,
    remote: remote
  } do
    set_remote(remote, Map.put(base, "name", "Remote name"))

    assert {output, :ok} = run_pull(tmp_dir)
    assert output =~ "Pull completed"
    assert local_name(tmp_dir) == "Remote name"

    assert {status_output, :ok} = run_captured(tmp_dir, fn -> Status.run() end, nil)
    assert status_output =~ "In sync"
  end

  test "in-sync pull succeeds and rewrites the baseline", %{tmp_dir: tmp_dir, base: base} do
    assert {output, :ok} = run_pull(tmp_dir)

    assert output =~ "Pull completed"
    assert baseline(tmp_dir) == base
  end

  test "pull without a baseline creates one", %{tmp_dir: tmp_dir, base: base} do
    File.rm!(Path.join(tmp_dir, ".src.json"))

    assert {_output, :ok} = run_pull(tmp_dir)

    assert baseline(tmp_dir) == base
  end

  test "pull into an empty directory succeeds", %{tmp_dir: tmp_dir, base: base} do
    File.rm_rf!(Path.join(tmp_dir, "src"))
    File.rm!(Path.join(tmp_dir, ".src.json"))

    assert {output, :ok} = run_pull(tmp_dir)

    assert output =~ "Pull completed"
    assert baseline(tmp_dir) == base
    assert element_dirs(tmp_dir) == ["tiptap-AAC"]
  end

  test "an entity deleted remotely disappears locally and is not pushed back", %{
    tmp_dir: tmp_dir,
    base: base,
    remote: remote
  } do
    set_remote(remote, base |> Map.put("plugin_elements", %{}) |> Map.put("plugin_actions", %{}))

    assert {_output, :ok} = run_pull(tmp_dir)

    assert element_dirs(tmp_dir) == []
    assert action_dirs(tmp_dir) == []

    assert {:ok, payload, []} = build_local(tmp_dir)
    assert payload["plugin_elements"] == %{}
    assert payload["plugin_actions"] == %{}
  end

  test "an element action deleted remotely leaves no orphaned file", %{
    tmp_dir: tmp_dir,
    base: base,
    remote: remote
  } do
    remote_plugin = update_in(base, ["plugin_elements", "AAC", "actions"], &Map.delete(&1, "ACR"))
    set_remote(remote, remote_plugin)

    assert {_output, :ok} = run_pull(tmp_dir)

    assert element_action_files(tmp_dir) == ["table-toggle-header-row-ACp.js"]
    assert {:ok, payload, []} = build_local(tmp_dir)
    assert Map.keys(payload["plugin_elements"]["AAC"]["actions"]) == ["ACp"]
  end

  test "files pled does not write are left alone", %{tmp_dir: tmp_dir, base: base, remote: remote} do
    notes = Path.join([tmp_dir, "src", "elements", "tiptap-AAC", "actions", "NOTES.md"])
    File.write!(notes, "mine")

    set_remote(
      remote,
      update_in(base, ["plugin_elements", "AAC", "actions"], &Map.delete(&1, "ACR"))
    )

    assert {_output, :ok} = run_pull(tmp_dir)

    assert File.read!(notes) == "mine"
    assert element_action_files(tmp_dir) == ["NOTES.md", "table-toggle-header-row-ACp.js"]
  end

  test "an entity renamed remotely leaves exactly one directory", %{
    tmp_dir: tmp_dir,
    base: base,
    remote: remote
  } do
    remote_plugin =
      base
      |> put_in(["plugin_elements", "AAC", "display"], "Editor")
      |> put_in(["plugin_actions", "AEK", "display"], "make token")

    set_remote(remote, remote_plugin)

    assert {_output, :ok} = run_pull(tmp_dir)

    assert element_dirs(tmp_dir) == ["editor-AAC"]
    assert action_dirs(tmp_dir) == ["make-token-AEK"]
  end

  test "an unreachable remote fails without touching local files", %{
    tmp_dir: tmp_dir,
    remote: remote
  } do
    change_local_name(tmp_dir, "Local name")
    set_get_error(remote, 400, %{"error" => "maintenance"})

    assert {output, {:error, {:remote_unreachable, reason}}} = run_pull(tmp_dir)

    assert reason =~ "HTTP 400"
    assert output =~ "Pull failed"
    assert local_name(tmp_dir) == "Local name"
  end

  test "a pull followed by a push uploads exactly the pulled payload", %{
    tmp_dir: tmp_dir,
    base: base,
    remote: remote
  } do
    set_remote(remote, Map.put(base, "plugin_actions", %{}))

    assert {_output, :ok} = run_pull(tmp_dir)
    assert {output, :ok} = run_captured(tmp_dir, fn -> Push.run([]) end, nil)

    assert output =~ "already in sync"
    assert uploads(remote) == []
  end

  defp run_pull(tmp_dir, opts \\ []) do
    run_captured(tmp_dir, fn -> Pull.run(opts) end, nil)
  end

  defp run_captured(tmp_dir, command, input) do
    caller = self()
    ref = make_ref()

    fun = fn ->
      result = File.cd!(tmp_dir, command)
      send(caller, {ref, result})
    end

    output = if is_nil(input), do: capture_io(fun), else: capture_io([input: input], fun)

    assert_receive {^ref, result}
    {output, result}
  end

  defp build_local(tmp_dir) do
    File.cd!(tmp_dir, fn -> Encoder.build() end)
  end

  defp stub_remote(initial_remote) do
    {:ok, agent} =
      Agent.start_link(fn -> %{remote: initial_remote, uploads: [], get_error: nil} end)

    Application.put_env(:pled, :test_adapter_fun, fn request ->
      case request.method do
        :get ->
          state = Agent.get(agent, & &1)

          response =
            case state.get_error do
              nil -> %Req.Response{status: 200, body: state.remote}
              {status, body} -> %Req.Response{status: status, body: body}
            end

          {request, response}

        :post ->
          sent = request.body |> IO.iodata_to_binary() |> Jason.decode!() |> Map.get("raw")

          Agent.update(agent, fn state ->
            %{state | remote: sent, uploads: state.uploads ++ [sent]}
          end)

          {request, %Req.Response{status: 200, body: %{}}}
      end
    end)

    agent
  end

  defp set_remote(agent, payload), do: Agent.update(agent, &%{&1 | remote: payload})

  defp set_get_error(agent, status, body) do
    Agent.update(agent, &%{&1 | get_error: {status, body}})
  end

  defp uploads(agent), do: Agent.get(agent, & &1.uploads)

  defp write_workspace(tmp_dir, plugin) do
    src_dir = Path.join(tmp_dir, "src")
    File.mkdir_p!(src_dir)
    File.write!(Path.join(src_dir, "plugin.json"), Jason.encode!(plugin, pretty: true))
    capture_io(fn -> assert :ok = Decoder.decode(plugin, tmp_dir) end)
  end

  defp change_local_name(tmp_dir, name) do
    path = Path.join([tmp_dir, "src", "plugin.json"])
    plugin = path |> File.read!() |> Jason.decode!() |> Map.put("name", name)
    File.write!(path, Jason.encode!(plugin, pretty: true))
  end

  defp local_name(tmp_dir) do
    [tmp_dir, "src", "plugin.json"]
    |> Path.join()
    |> File.read!()
    |> Jason.decode!()
    |> Map.get("name")
  end

  defp baseline(tmp_dir) do
    tmp_dir |> Path.join(".src.json") |> File.read!() |> Jason.decode!()
  end

  defp element_dirs(tmp_dir), do: list_dir([tmp_dir, "src", "elements"])
  defp action_dirs(tmp_dir), do: list_dir([tmp_dir, "src", "actions"])

  defp element_action_files(tmp_dir),
    do: list_dir([tmp_dir, "src", "elements", "tiptap-AAC", "actions"])

  defp list_dir(parts) do
    case parts |> Path.join() |> File.ls() do
      {:ok, entries} -> Enum.sort(entries)
      {:error, :enoent} -> []
    end
  end

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
