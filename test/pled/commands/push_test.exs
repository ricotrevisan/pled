defmodule Pled.Commands.PushTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Pled.Commands.{Decoder, Push}

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

  test "local-ahead uploads without prompting, saves the sent baseline, and next push is in sync",
       %{
         tmp_dir: tmp_dir,
         remote: remote
       } do
    change_local_name(tmp_dir, "Local name")
    Application.put_env(:pled, :interactive, true)

    assert {output, :ok} = run_push(tmp_dir, [], "")
    assert output =~ "Push completed"
    refute output =~ "Continue"
    refute output =~ "Apply these changes"

    assert [sent] = uploads(remote)
    assert sent["name"] == "Local name"
    assert Jason.decode!(File.read!(Path.join(tmp_dir, ".src.json"))) == sent
    assert Jason.decode!(File.read!(Path.join([tmp_dir, "dist", "plugin.json"]))) == sent
    assert request_counts(remote) == %{get: 1, post: 1}

    assert {second_output, :ok} = run_push(tmp_dir, force: true)
    assert second_output =~ "already in sync"
    assert second_output =~ "--force flag was ignored"
    assert uploads(remote) == [sent]
    assert request_counts(remote) == %{get: 2, post: 1}
  end

  test "in-sync makes no upload or dist file", %{tmp_dir: tmp_dir, remote: remote} do
    assert {output, :ok} = run_push(tmp_dir)

    assert output =~ "In sync"
    assert output =~ "nothing uploaded"
    assert uploads(remote) == []
    refute File.exists?(Path.join(tmp_dir, "dist"))
  end

  for state <- [:remote_ahead, :diverged] do
    test "#{state} refuses without force and gives resolution guidance", %{
      tmp_dir: tmp_dir,
      base: base,
      remote: remote
    } do
      set_remote(remote, Map.put(base, "name", "Remote name"))

      if unquote(state) == :diverged do
        change_local_name(tmp_dir, "Local name")
      end

      assert {output, {:error, unquote(state)}} = run_push(tmp_dir)

      assert output =~ "Push refused"
      assert output =~ "`pled pull"
      refute output =~ "Push failed:"
      assert uploads(remote) == []
    end
  end

  for state <- [:remote_ahead, :diverged] do
    test "--force uploads in #{state} and identifies discarded remote changes", %{
      tmp_dir: tmp_dir,
      base: base,
      remote: remote
    } do
      set_remote(remote, Map.put(base, "name", "Remote name"))

      if unquote(state) == :diverged do
        change_local_name(tmp_dir, "Local name")
      end

      assert {output, :ok} = run_push(tmp_dir, force: true)

      assert output =~ "Force push will discard these remote changes"
      assert output =~ "Metadata field changed"
      assert length(uploads(remote)) == 1
    end
  end

  test "no baseline refuses non-interactively and names --force", %{
    tmp_dir: tmp_dir,
    remote: remote
  } do
    File.rm!(Path.join(tmp_dir, ".src.json"))

    assert {output, {:error, :no_baseline}} = run_push(tmp_dir)

    assert output =~ "non-interactive"
    assert output =~ "`pled push --force`"
    assert uploads(remote) == []
  end

  test "no baseline can be confirmed interactively", %{tmp_dir: tmp_dir, remote: remote} do
    File.rm!(Path.join(tmp_dir, ".src.json"))
    Application.put_env(:pled, :interactive, true)

    assert {output, :ok} = run_push(tmp_dir, [], "y\n")

    assert output =~ "Push without a baseline?"
    assert length(uploads(remote)) == 1
  end

  test "EOF safely declines a no-baseline prompt", %{tmp_dir: tmp_dir, remote: remote} do
    File.rm!(Path.join(tmp_dir, ".src.json"))
    Application.put_env(:pled, :interactive, true)

    assert {_output, {:error, :cancelled}} = run_push(tmp_dir, [], "")
    assert uploads(remote) == []
  end

  test "--force proceeds without a baseline in a non-interactive session", %{
    tmp_dir: tmp_dir,
    remote: remote
  } do
    File.rm!(Path.join(tmp_dir, ".src.json"))

    assert {output, :ok} = run_push(tmp_dir, force: true)

    assert output =~ "Force pushing without a baseline"
    assert length(uploads(remote)) == 1
  end

  test "a baseline write failure warns loudly without failing the successful upload", %{
    tmp_dir: tmp_dir,
    remote: remote
  } do
    change_local_name(tmp_dir, "Local name")
    invalid_path = Path.join([tmp_dir, "missing", ".src.json"])
    set_on_post(remote, fn -> Application.put_env(:pled, :src_snapshot_file, invalid_path) end)

    assert {output, :ok} = run_push(tmp_dir)

    assert output =~ "Plugin uploaded, but the baseline was not updated"
    assert output =~ "`pled status`"
    assert length(uploads(remote)) == 1
  end

  test "CLI marks push refusals as already reported", %{
    tmp_dir: tmp_dir,
    base: base,
    remote: remote
  } do
    set_remote(remote, Map.put(base, "name", "Remote name"))

    assert {output, {:error, {:reported, :remote_ahead}}} = run_cli_push(tmp_dir)
    assert output =~ "Push refused"
    refute output =~ "Push failed:"
  end

  test "local validation issues refuse non-interactive push without uploading", %{
    tmp_dir: tmp_dir,
    remote: remote
  } do
    change_first_field_caption(tmp_dir)

    assert {output, {:error, :unresolved_issues}} = run_push(tmp_dir)

    assert output =~ "field"
    assert output =~ "non-interactive"
    assert output =~ "`pled push` from a terminal"
    assert uploads(remote) == []
    refute File.exists?(Path.join(tmp_dir, "dist"))
  end

  test "watch's internal legacy path bypasses Sync and retains its RemoteChecker flow", %{
    tmp_dir: tmp_dir,
    remote: remote
  } do
    assert {output, :ok} = run_push(tmp_dir, force: true, sync: false)

    assert output =~ "Push completed"
    refute output =~ "already in sync"
    assert length(uploads(remote)) == 1
    assert request_counts(remote) == %{get: 1, post: 1}
  end

  test "remote fetch failures are not bypassed by --force", %{tmp_dir: tmp_dir, remote: remote} do
    set_get_error(remote, 400, %{"error" => "maintenance"})

    assert {output, {:error, {:remote_unreachable, reason}}} =
             run_push(tmp_dir, force: true)

    assert reason =~ "HTTP 400"
    assert output =~ "maintenance"
    assert uploads(remote) == []
  end

  defp run_push(tmp_dir, opts \\ [], input \\ nil) do
    run_captured(tmp_dir, fn -> Push.run(opts) end, input)
  end

  defp run_cli_push(tmp_dir, opts \\ []) do
    run_captured(tmp_dir, fn -> Pled.handle_command({:push, opts}) end, nil)
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

  defp stub_remote(initial_remote) do
    {:ok, agent} =
      Agent.start_link(fn ->
        %{
          remote: initial_remote,
          uploads: [],
          get_count: 0,
          post_count: 0,
          get_error: nil,
          on_post: fn -> :ok end
        }
      end)

    Application.put_env(:pled, :test_adapter_fun, fn request ->
      case request.method do
        :get ->
          state = Agent.get(agent, & &1)
          Agent.update(agent, &Map.update!(&1, :get_count, fn count -> count + 1 end))

          response =
            case state.get_error do
              nil -> %Req.Response{status: 200, body: state.remote}
              {status, body} -> %Req.Response{status: status, body: body}
            end

          {request, response}

        :post ->
          body = request.body |> IO.iodata_to_binary() |> Jason.decode!()
          sent = body["raw"]
          on_post = Agent.get(agent, & &1.on_post)
          on_post.()

          Agent.update(agent, fn state ->
            %{
              state
              | remote: sent,
                uploads: state.uploads ++ [sent],
                post_count: state.post_count + 1
            }
          end)

          {request, %Req.Response{status: 200, body: %{}}}
      end
    end)

    agent
  end

  defp set_remote(agent, payload), do: Agent.update(agent, &%{&1 | remote: payload})
  defp set_on_post(agent, fun), do: Agent.update(agent, &%{&1 | on_post: fun})

  defp set_get_error(agent, status, body) do
    Agent.update(agent, &%{&1 | get_error: {status, body}})
  end

  defp uploads(agent), do: Agent.get(agent, & &1.uploads)

  defp request_counts(agent) do
    Agent.get(agent, &%{get: &1.get_count, post: &1.post_count})
  end

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

  defp change_first_field_caption(tmp_dir) do
    [fields_path | _] = Path.wildcard(Path.join([tmp_dir, "src", "elements", "*", "fields.txt"]))
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
