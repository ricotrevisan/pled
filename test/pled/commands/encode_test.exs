defmodule Pled.Commands.EncodeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Pled.Commands.Encoder

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    original = Application.get_env(:pled, :interactive)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:pled, :interactive)
      else
        Application.put_env(:pled, :interactive, original)
      end
    end)

    priv_dir = :code.priv_dir(:pled) |> to_string()

    src_dir = Path.join(tmp_dir, "src")
    element_dir = Path.join([src_dir, "elements", "test-element-AAC"])
    File.mkdir_p!(element_dir)

    File.write!(Path.join(src_dir, "plugin.json"), Jason.encode!(%{"name" => "Test plugin"}))

    File.cp!(
      Path.join(priv_dir, "examples/single_element.json"),
      Path.join(element_dir, "AAC.json")
    )

    for js <- ["initialize.js", "update.js", "reset.js", "preview.js"] do
      File.write!(Path.join(element_dir, js), "console.log('test');")
    end

    File.write!(Path.join(element_dir, "fields.txt"), """
    Header font color (ADe)
    Allowed MIME Types (AFz)
    """)

    actions_dir = Path.join(element_dir, "actions")
    File.mkdir_p!(actions_dir)
    File.write!(Path.join(actions_dir, "table-toggle-header-row-ACp.js"), "toggle();")
    File.write!(Path.join(actions_dir, "remove-link-ACR.js"), "removeLink();")

    cwd = File.cwd!()
    File.cd!(tmp_dir)
    on_exit(fn -> File.cd!(cwd) end)

    {:ok, element_dir: element_dir, dist_path: Path.join(tmp_dir, "dist/plugin.json")}
  end

  defp change_caption(element_dir) do
    File.write!(Path.join(element_dir, "fields.txt"), """
    Renamed caption (ADe)
    Allowed MIME Types (AFz)
    """)
  end

  test "clean tree encodes without prompting and writes dist/plugin.json", %{
    dist_path: dist_path
  } do
    Application.put_env(:pled, :interactive, false)

    capture_io(fn -> send(self(), {:result, Encoder.encode()}) end)

    assert_received {:result, :ok}

    payload = dist_path |> File.read!() |> Jason.decode!()

    assert get_in(payload, ["plugin_elements", "AAC", "fields", "ADe", "caption"]) ==
             "Header font color"

    assert get_in(payload, ["plugin_elements", "AAC", "actions", "ACp", "code", "fn"]) =~
             "toggle();"
  end

  test "non-interactive encode fails listing the issues and writes nothing", %{
    element_dir: element_dir,
    dist_path: dist_path
  } do
    Application.put_env(:pled, :interactive, false)
    change_caption(element_dir)

    output = capture_io(fn -> send(self(), {:result, Encoder.encode()}) end)

    assert_received {:result, {:error, :unresolved_issues}}
    assert output =~ "field ADe caption"
    assert output =~ "\"Header font color\" → \"Renamed caption\""
    assert output =~ "non-interactive"
    refute File.exists?(dist_path)
  end

  test "interactive encode applies the issues after confirmation", %{
    element_dir: element_dir,
    dist_path: dist_path
  } do
    Application.put_env(:pled, :interactive, true)
    change_caption(element_dir)

    output =
      capture_io([input: "y\n"], fn -> send(self(), {:result, Encoder.encode()}) end)

    assert_received {:result, :ok}
    assert output =~ "field ADe caption"

    payload = dist_path |> File.read!() |> Jason.decode!()

    assert get_in(payload, ["plugin_elements", "AAC", "fields", "ADe", "caption"]) ==
             "Renamed caption"
  end

  test "interactive encode aborts without writing when declined", %{
    element_dir: element_dir,
    dist_path: dist_path
  } do
    Application.put_env(:pled, :interactive, true)
    change_caption(element_dir)

    capture_io([input: "n\n"], fn -> send(self(), {:result, Encoder.encode()}) end)

    assert_received {:result, {:error, :cancelled}}
    refute File.exists?(dist_path)
  end

  test "action mismatch surfaces as an issue and is auto-fixed on confirmation", %{
    element_dir: element_dir,
    dist_path: dist_path
  } do
    Application.put_env(:pled, :interactive, false)
    File.write!(Path.join([element_dir, "actions", "new-action-XYZ.js"]), "newAction();")

    output = capture_io(fn -> send(self(), {:result, Encoder.encode()}) end)

    assert_received {:result, {:error, :unresolved_issues}}
    assert output =~ "element actions out of sync"
    assert output =~ "create action XYZ"
    refute File.exists?(dist_path)

    Application.put_env(:pled, :interactive, true)

    capture_io([input: "y\n"], fn -> send(self(), {:result, Encoder.encode()}) end)

    assert_received {:result, :ok}

    payload = dist_path |> File.read!() |> Jason.decode!()
    new_action = get_in(payload, ["plugin_elements", "AAC", "actions", "XYZ"])
    assert new_action["caption"] == "new action"
    assert new_action["code"]["fn"] =~ "newAction();"
  end
end
