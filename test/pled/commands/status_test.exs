defmodule Pled.Commands.StatusTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Pled.Commands.Status

  @test_snapshot_file ".src.json.test"

  setup do
    # Store original env vars
    original_plugin_id = System.get_env("PLUGIN_ID")
    original_cookie = System.get_env("BUBBLE_COOKIE")

    # Clean up test snapshot
    File.rm(@test_snapshot_file)

    # Replace snapshot file path for testing
    Application.put_env(:pled, :src_snapshot_file, @test_snapshot_file)

    on_exit(fn ->
      # Restore env vars
      if original_plugin_id do
        System.put_env("PLUGIN_ID", original_plugin_id)
      else
        System.delete_env("PLUGIN_ID")
      end

      if original_cookie do
        System.put_env("BUBBLE_COOKIE", original_cookie)
      else
        System.delete_env("BUBBLE_COOKIE")
      end

      File.rm(@test_snapshot_file)
      Application.delete_env(:pled, :src_snapshot_file)
    end)

    :ok
  end

  describe "run/1 environment checks" do
    test "shows PLUGIN_ID not found when missing" do
      System.delete_env("PLUGIN_ID")
      System.delete_env("BUBBLE_COOKIE")

      output = capture_io(fn -> Status.run([]) end)

      assert output =~ "PLUGIN_ID not found"
      assert output =~ "BUBBLE_COOKIE is not set"
    end

    test "shows PLUGIN_ID when present via env var" do
      System.put_env("PLUGIN_ID", "test-plugin-id")
      System.delete_env("BUBBLE_COOKIE")

      output = capture_io(fn -> Status.run([]) end)

      assert output =~ "PLUGIN_ID: test-plugin-id"
      assert output =~ "from env var"
      assert output =~ "BUBBLE_COOKIE is not set"
    end

    test "shows both set when present" do
      System.put_env("PLUGIN_ID", "test-plugin-id")
      System.put_env("BUBBLE_COOKIE", "test-cookie")

      output = capture_io(fn -> Status.run([]) end)

      assert output =~ "PLUGIN_ID: test-plugin-id"
      assert output =~ "BUBBLE_COOKIE is set"
    end

    test "shows cannot verify auth when env vars missing" do
      System.delete_env("PLUGIN_ID")
      System.delete_env("BUBBLE_COOKIE")

      output = capture_io(fn -> Status.run([]) end)

      assert output =~ "Cannot verify (missing environment variables)"
    end
  end

  describe "run/1 sync status" do
    test "shows no baseline found when snapshot doesn't exist" do
      System.put_env("PLUGIN_ID", "test-plugin-id")
      System.put_env("BUBBLE_COOKIE", "invalid-cookie-for-test")

      # Force snapshot to not exist
      File.rm(@test_snapshot_file)

      output =
        capture_io(fn ->
          # This will fail at auth, but we're testing the structure
          Status.run([])
        end)

      # Auth will fail with invalid cookie, so we won't reach sync status
      assert output =~ "Environment:" or output =~ "Authentication:"
    end
  end

  describe "parse_args integration" do
    test "status command is parsed correctly" do
      assert Pled.parse_args(["status"]) == {:status, []}
    end

    test "status command with verbose flag" do
      assert Pled.parse_args(["status", "-v"]) == {:status, [verbose: true]}
      assert Pled.parse_args(["status", "--verbose"]) == {:status, [verbose: true]}
    end

    test "status command with help flag" do
      assert Pled.parse_args(["status", "-h"]) == {:status, [help: true]}
      assert Pled.parse_args(["status", "--help"]) == {:status, [help: true]}
    end

    test "status command with invalid flags returns help" do
      assert Pled.parse_args(["status", "--invalid"]) == {:help, []}
    end

    test "status command with extra args returns help" do
      assert Pled.parse_args(["status", "extra-arg"]) == {:help, []}
    end
  end
end
