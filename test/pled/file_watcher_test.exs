defmodule Pled.FileWatcherTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Pled.Commands.{Decoder, Watch}
  alias Pled.FileWatcher

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    previous = %{
      cwd: File.cwd!(),
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
      File.cd!(previous.cwd)
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
    File.cd!(tmp_dir)

    {:ok, base: base, remote: remote}
  end

  test "a saved file triggers a push while the remote is clean", %{remote: remote} do
    output =
      watching(
        fn ->
          # Let the OS watcher come up before the only edit of the test.
          Process.sleep(300)
          change_local_name("Local name")
          wait_until("the local edit to be uploaded", fn -> uploads(remote) != [] end, 15_000)
        end,
        # Only the file event can drive a cycle within the test.
        poll_interval_ms: 60_000
      )

    assert output =~ "File changed:"
    assert output =~ "Push completed"
    assert [sent] = uploads(remote)
    assert sent["name"] == "Local name"
    assert Jason.decode!(File.read!(".src.json")) == sent
  end

  test "rapid successive saves collapse into a single push", %{remote: remote} do
    output =
      watching(
        fn ->
          Enum.each(1..5, fn index ->
            change_local_name("Local name #{index}")
            Process.sleep(20)
          end)

          wait_until("the debounced push", fn -> uploads(remote) != [] end, 15_000)
          Process.sleep(500)
        end,
        debounce_ms: 200,
        poll_interval_ms: 60_000
      )

    assert [sent] = uploads(remote)
    assert sent["name"] == "Local name 5"
    assert output =~ "Push completed"
  end

  test "a remote change is pulled and does not trigger a push back", %{
    base: base,
    remote: remote
  } do
    output =
      watching(fn ->
        set_remote(remote, Map.put(base, "name", "Remote name"))
        wait_until("the remote change to land locally", fn -> local_name() == "Remote name" end)
        # Outlive the settle window so the decoder's own writes could have pushed.
        Process.sleep(800)
      end)

    assert output =~ "Remote changes detected"
    assert output =~ "Remote changes pulled"
    assert uploads(remote) == []
    assert Jason.decode!(File.read!(".src.json"))["name"] == "Remote name"
  end

  test "divergence holds the watcher with a conflict banner and no network writes", %{
    base: base,
    remote: remote
  } do
    change_local_name("Local name")
    set_remote(remote, Map.put(base, "name", "Remote name"))

    output =
      watching(fn ->
        wait_until("several remote checks", fn -> length(get_times(remote)) >= 4 end)
      end)

    assert output =~ "Watch paused: local and remote both changed"
    assert output =~ "`pled pull --wipe`"
    assert output =~ "`pled push --force`"
    assert uploads(remote) == []
    assert local_name() == "Local name"
    # The banner is printed once, not on every tick.
    assert occurrences(output, "Watch paused") == 1
  end

  test "watch resumes on its own once the divergence is resolved", %{
    base: base,
    remote: remote
  } do
    change_local_name("Local name")
    set_remote(remote, Map.put(base, "name", "Remote name"))

    output =
      watching(fn ->
        wait_until("the conflict banner", fn -> length(get_times(remote)) >= 2 end)
        change_local_name(base["name"])
        wait_until("the remote change to land locally", fn -> local_name() == "Remote name" end)
      end)

    assert output =~ "Divergence resolved; watch resuming"
    assert output =~ "Remote changes pulled"
    assert uploads(remote) == []
  end

  test "validation issues report an error and skip the push", %{remote: remote} do
    Application.put_env(:pled, :interactive, true)

    output =
      watching(fn ->
        change_first_field_caption()
        wait_until("two remote checks", fn -> length(get_times(remote)) >= 2 end)
      end)

    assert output =~ "non-interactive session"
    assert output =~ "Push skipped"
    refute output =~ "Apply these changes and continue?"
    assert uploads(remote) == []
    refute File.exists?("dist")
  end

  test "repeated remote errors back off exponentially", %{remote: remote} do
    set_get_response(remote, 400, %{"error" => "boom"})

    output =
      watching(
        fn ->
          wait_until("four failed remote checks", fn -> length(get_times(remote)) >= 4 end, 8_000)
        end,
        poll_interval_ms: 100
      )

    assert output =~ "Sync failed"

    [first, second, third | _] = gaps(get_times(remote))
    assert second > first
    assert third > second
  end

  test "an expired cookie is reported loudly on every check", %{remote: remote} do
    set_get_response(remote, 401, %{"message" => "not logged in"})

    output =
      watching(fn ->
        wait_until("two failed remote checks", fn -> length(get_times(remote)) >= 2 end)
      end)

    assert occurrences(output, "Refresh BUBBLE_COOKIE") >= 2
    assert output =~ "unauthorized"
  end

  test "verbose mode prints a one-line summary per cycle", %{remote: remote} do
    output =
      watching(
        fn -> wait_until("two remote checks", fn -> length(get_times(remote)) >= 2 end) end,
        verbose: true
      )

    assert output =~ "[watch] state=in_sync action=none hold=false"
  end

  test "watch refuses to start without a src directory", %{tmp_dir: tmp_dir} do
    File.rm_rf!(Path.join(tmp_dir, "src"))

    assert {output, {:error, :no_src}} = run_watch()
    assert output =~ "No src/ directory found"
    assert output =~ "`pled pull`"
  end

  test "watch refuses to start without a baseline", %{tmp_dir: tmp_dir} do
    File.rm!(Path.join(tmp_dir, ".src.json"))

    assert {output, {:error, :no_baseline}} = run_watch()
    assert output =~ "No baseline snapshot"
    assert output =~ "`pled pull`"
  end

  test "watch rejects a non-positive polling interval" do
    assert {output, {:error, :invalid_interval}} = run_watch(interval: 0)
    assert output =~ "--interval must be at least 1 second"
  end

  test "the CLI parses the polling interval" do
    assert {:watch, opts} = Pled.parse_args(["watch", "--interval", "60", "-v"])
    assert opts[:interval] == 60
    assert opts[:verbose]

    assert {:watch, opts} = Pled.parse_args(["watch", "-i", "5"])
    assert opts[:interval] == 5
  end

  defp watching(fun, opts \\ []) do
    opts =
      Keyword.merge(
        [poll_interval_ms: 100, debounce_ms: 50, pull_settle_ms: 1_500],
        opts
      )

    capture_io(fn ->
      {:ok, pid} = FileWatcher.start_link(opts)

      try do
        fun.()
      after
        GenServer.stop(pid)
      end
    end)
  end

  defp run_watch(opts \\ []) do
    caller = self()
    ref = make_ref()

    output = capture_io(fn -> send(caller, {ref, Watch.run(opts)}) end)

    assert_receive {^ref, result}
    {output, result}
  end

  defp occurrences(output, needle), do: length(String.split(output, needle)) - 1

  defp wait_until(label, fun, timeout \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_wait_until(label, fun, deadline)
  end

  defp do_wait_until(label, fun, deadline) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        raise "timed out waiting for #{label}"

      true ->
        Process.sleep(25)
        do_wait_until(label, fun, deadline)
    end
  end

  defp gaps(times) do
    times
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [earlier, later] -> later - earlier end)
  end

  defp stub_remote(initial_remote) do
    {:ok, agent} =
      Agent.start_link(fn ->
        %{remote: initial_remote, uploads: [], get_times: [], get_response: nil}
      end)

    Application.put_env(:pled, :test_adapter_fun, fn request ->
      case request.method do
        :get ->
          state =
            Agent.get_and_update(agent, fn state ->
              {state,
               Map.update!(state, :get_times, &(&1 ++ [System.monotonic_time(:millisecond)]))}
            end)

          response =
            case state.get_response do
              nil -> %Req.Response{status: 200, body: state.remote}
              {status, body} -> %Req.Response{status: status, body: body}
            end

          {request, response}

        :post ->
          sent = request.body |> IO.iodata_to_binary() |> Jason.decode!() |> Map.fetch!("raw")

          Agent.update(agent, fn state ->
            %{state | remote: sent, uploads: state.uploads ++ [sent]}
          end)

          {request, %Req.Response{status: 200, body: %{}}}
      end
    end)

    agent
  end

  defp set_remote(agent, payload), do: Agent.update(agent, &%{&1 | remote: payload})

  defp set_get_response(agent, status, body) do
    Agent.update(agent, &%{&1 | get_response: {status, body}})
  end

  defp uploads(agent), do: Agent.get(agent, & &1.uploads)
  defp get_times(agent), do: Agent.get(agent, & &1.get_times)

  defp write_workspace(tmp_dir, plugin) do
    src_dir = Path.join(tmp_dir, "src")
    File.mkdir_p!(src_dir)
    File.write!(Path.join(src_dir, "plugin.json"), Jason.encode!(plugin, pretty: true))
    capture_io(fn -> assert :ok = Decoder.decode(plugin, tmp_dir) end)
  end

  defp change_local_name(name) do
    path = Path.join("src", "plugin.json")
    plugin = path |> File.read!() |> Jason.decode!() |> Map.put("name", name)
    File.write!(path, Jason.encode!(plugin, pretty: true))
  end

  defp local_name do
    Path.join("src", "plugin.json") |> File.read!() |> Jason.decode!() |> Map.get("name")
  end

  defp change_first_field_caption do
    [fields_path | _] = Path.wildcard(Path.join(["src", "elements", "*", "fields.txt"]))
    [first_line | rest] = fields_path |> File.read!() |> String.split("\n")
    [_line, key] = Regex.run(~r/^.* \(([^)]+)\)$/, first_line)
    File.write!(fields_path, Enum.join(["Changed caption (#{key})" | rest], "\n"))
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
