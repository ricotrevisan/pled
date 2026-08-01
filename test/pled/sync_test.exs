defmodule Pled.SyncTest do
  use ExUnit.Case, async: false

  alias Pled.Sync

  describe "classify/3" do
    test "classifies the complete fingerprint matrix" do
      assert Sync.classify("base", "base", "base") == :in_sync
      assert Sync.classify("base", "local", "base") == :local_ahead
      assert Sync.classify("base", "base", "remote") == :remote_ahead
      assert Sync.classify("base", "local", "remote") == :diverged
      assert Sync.classify("base", "changed", "changed") == :diverged
    end

    test "classifies a missing baseline as its own state" do
      assert Sync.classify(nil, "local", "remote") == :no_baseline
    end
  end
end
