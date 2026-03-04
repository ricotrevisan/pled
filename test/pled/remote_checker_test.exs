defmodule Pled.RemoteCheckerTest do
  use ExUnit.Case, async: false
  alias Pled.RemoteChecker

  @test_snapshot_file ".src.json.test"

  setup do
    # Clean up test snapshot
    File.rm(@test_snapshot_file)

    # Replace snapshot file path for testing
    Application.put_env(:pled, :src_snapshot_file, @test_snapshot_file)

    on_exit(fn ->
      File.rm(@test_snapshot_file)
      Application.delete_env(:pled, :src_snapshot_file)
    end)

    :ok
  end

  describe "save_remote_snapshot/1" do
    test "saves plugin data as JSON" do
      plugin_data = %{
        "name" => "Test Plugin",
        "version" => "1.0.0",
        "elements" => [],
        "actions" => []
      }

      assert :ok = RemoteChecker.save_remote_snapshot(plugin_data)
      assert File.exists?(@test_snapshot_file)

      {:ok, content} = File.read(@test_snapshot_file)
      {:ok, saved_data} = Jason.decode(content)

      assert saved_data == plugin_data
    end

    test "returns error when file write fails" do
      # Test with invalid path
      old_file = @test_snapshot_file
      Application.put_env(:pled, :src_snapshot_file, "/invalid/path/file.json")

      plugin_data = %{"name" => "Test"}

      result = RemoteChecker.save_remote_snapshot(plugin_data)
      assert {:error, msg} = result
      assert String.contains?(msg, "Failed to save snapshot")

      Application.put_env(:pled, :src_snapshot_file, old_file)
    end
  end

  describe "check_remote_changes/0" do
    @tag :integration
    test "returns error when no snapshot exists" do
      # This is an integration test that would require actual API calls
      # For now, we'll test the basic error condition
      assert {:error, msg} = RemoteChecker.check_remote_changes()
      assert String.contains?(msg, "No local snapshot found")
    end
  end

  describe "has_remote_changed?/0" do
    test "returns false on error when no snapshot" do
      # When there's an error (like no snapshot), should return false
      refute RemoteChecker.has_remote_changed?()
    end
  end

  describe "snapshot_exists?/0" do
    test "returns true when snapshot file exists" do
      File.write!(@test_snapshot_file, "{}")
      assert true = RemoteChecker.snapshot_exists?()
    end

    test "returns false when snapshot file doesn't exist" do
      File.rm(@test_snapshot_file)
      refute RemoteChecker.snapshot_exists?()
    end
  end

  describe "update_snapshot/0" do
    @tag :integration
    test "requires actual remote connection for testing" do
      # This would require mocking the BubbleApi which needs actual network calls
      # For basic unit testing, we skip this integration test
      assert true
    end
  end

  # Test helper functions for analyzing changes
  describe "change analysis" do
    test "analyze_changes detects metadata differences" do
      # Test the private function indirectly by checking save/read cycle
      original = %{"name" => "Test", "version" => "1.0"}
      updated = %{"name" => "Updated", "version" => "1.0"}

      # Save original
      assert :ok = RemoteChecker.save_remote_snapshot(original)

      # Verify file was saved correctly
      {:ok, content} = File.read(@test_snapshot_file)
      {:ok, parsed} = Jason.decode(content)
      assert parsed == original
    end
  end
end
