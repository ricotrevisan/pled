defmodule Pled.Commands.HelpTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias Pled.Commands.{
    Pull,
    Push,
    Encoder,
    Upload,
    Watch,
    Init,
    CheckRemote,
    Status,
    Help
  }

  describe "general help" do
    test "displays usage overview" do
      output = capture_io(fn -> Help.run() end)
      assert output =~ "Bubble.io Plugin Development Tool"
      assert output =~ "pled pull"
      assert output =~ "pled push"
      assert output =~ "pled encode"
      assert output =~ "pled upload"
      assert output =~ "pled watch"
      assert output =~ "pled init"
      assert output =~ "pled check-remote"
      assert output =~ "pled status"
    end

    test "mentions per-command help" do
      output = capture_io(fn -> Help.run() end)
      assert output =~ "pled help <command>"
    end
  end

  describe "pull help" do
    test "displays pull-specific help" do
      output = capture_io(fn -> Pull.help() end)
      assert output =~ "pled pull"
      assert output =~ "--wipe"
      assert output =~ "--verbose"
      assert output =~ "--help"
    end

    test "returns :ok" do
      capture_io(fn ->
        assert Pull.help() == :ok
      end)
    end
  end

  describe "push help" do
    test "displays push-specific help" do
      output = capture_io(fn -> Push.help() end)
      assert output =~ "pled push"
      assert output =~ "--force"
      assert output =~ "--verbose"
      assert output =~ "--help"
    end

    test "returns :ok" do
      capture_io(fn ->
        assert Push.help() == :ok
      end)
    end
  end

  describe "encode help" do
    test "displays encode-specific help" do
      output = capture_io(fn -> Encoder.help() end)
      assert output =~ "pled encode"
      assert output =~ "--verbose"
      assert output =~ "--help"
      assert output =~ "dist/plugin.json"
    end

    test "returns :ok" do
      capture_io(fn ->
        assert Encoder.help() == :ok
      end)
    end
  end

  describe "upload help" do
    test "displays upload-specific help" do
      output = capture_io(fn -> Upload.help() end)
      assert output =~ "pled upload"
      assert output =~ "<file_path>"
      assert output =~ "--verbose"
      assert output =~ "--help"
    end

    test "returns :ok" do
      capture_io(fn ->
        assert Upload.help() == :ok
      end)
    end
  end

  describe "watch help" do
    test "displays watch-specific help" do
      output = capture_io(fn -> Watch.help() end)
      assert output =~ "pled watch"
      assert output =~ "--verbose"
      assert output =~ "--help"
      assert output =~ "src/"
    end

    test "returns :ok" do
      capture_io(fn ->
        assert Watch.help() == :ok
      end)
    end
  end

  describe "init help" do
    test "displays init-specific help" do
      output = capture_io(fn -> Init.help() end)
      assert output =~ "pled init"
      assert output =~ "--react"
      assert output =~ "--verbose"
      assert output =~ "--help"
      assert output =~ "url_or_id"
    end

    test "returns :ok" do
      capture_io(fn ->
        assert Init.help() == :ok
      end)
    end
  end

  describe "check-remote help" do
    test "displays check-remote-specific help" do
      output = capture_io(fn -> CheckRemote.help() end)
      assert output =~ "pled check-remote"
      assert output =~ "--verbose"
      assert output =~ "--help"
    end

    test "returns :ok" do
      capture_io(fn ->
        assert CheckRemote.help() == :ok
      end)
    end
  end

  describe "status help" do
    test "displays status-specific help" do
      output = capture_io(fn -> Status.help() end)
      assert output =~ "pled status"
      assert output =~ "--verbose"
      assert output =~ "--help"
    end

    test "returns :ok" do
      capture_io(fn ->
        assert Status.help() == :ok
      end)
    end
  end

  describe "handle_command with --help flag" do
    test "pull --help shows help instead of running" do
      output =
        capture_io(fn ->
          assert Pled.handle_command({:pull, [help: true]}) == :ok
        end)

      assert output =~ "pled pull"
      assert output =~ "--wipe"
    end

    test "push --help shows help instead of running" do
      output =
        capture_io(fn ->
          assert Pled.handle_command({:push, [help: true]}) == :ok
        end)

      assert output =~ "pled push"
      assert output =~ "--force"
    end

    test "encode --help shows help instead of running" do
      output =
        capture_io(fn ->
          assert Pled.handle_command({:encode, [help: true]}) == :ok
        end)

      assert output =~ "pled encode"
    end

    test "upload --help shows help instead of running" do
      output =
        capture_io(fn ->
          assert Pled.handle_command({:upload, {"", [help: true]}}) == :ok
        end)

      assert output =~ "pled upload"
    end

    test "watch --help shows help instead of running" do
      output =
        capture_io(fn ->
          assert Pled.handle_command({:watch, [help: true]}) == :ok
        end)

      assert output =~ "pled watch"
    end

    test "init --help shows help instead of running" do
      output =
        capture_io(fn ->
          assert Pled.handle_command({:init, [help: true]}) == :ok
        end)

      assert output =~ "pled init"
    end

    test "check-remote --help shows help instead of running" do
      output =
        capture_io(fn ->
          assert Pled.handle_command({:check_remote, [help: true]}) == :ok
        end)

      assert output =~ "pled check-remote"
    end

    test "status --help shows help instead of running" do
      output =
        capture_io(fn ->
          assert Pled.handle_command({:status, [help: true]}) == :ok
        end)

      assert output =~ "pled status"
    end
  end
end
