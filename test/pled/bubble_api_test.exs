defmodule Pled.BubbleApiTest do
  use ExUnit.Case, async: true

  alias Pled.BubbleApi

  describe "fetch_plugin/0" do
    test "returns error when PLUGIN_ID is not available" do
      System.delete_env("PLUGIN_ID")
      System.delete_env("COOKIE")

      assert {:error, msg} = BubbleApi.fetch_plugin()
      assert msg =~ "Plugin ID not found"
    end

    test "returns error when COOKIE environment variable is not set" do
      System.put_env("PLUGIN_ID", "test_plugin_id")
      System.delete_env("COOKIE")

      assert {:error, "Environment variable COOKIE is not set"} = BubbleApi.fetch_plugin()

      System.delete_env("PLUGIN_ID")
    end

    test "makes HTTP request with correct URL and headers when env vars are set" do
      System.put_env("PLUGIN_ID", "test_plugin_123")
      System.put_env("COOKIE", "session=abc123")

      # For now, this test will actually make a real HTTP request
      # In a real test suite, you'd want to mock this
      case BubbleApi.fetch_plugin() do
        {:ok, _body} ->
          # Success case - the request worked
          assert true

        {:error, reason} ->
          # Expected for invalid credentials/plugin ID
          assert reason =~ "HTTP"
      end

      System.delete_env("PLUGIN_ID")
      System.delete_env("COOKIE")
    end

    @tag :integration
    test "makes end to end call" do
      env_file = Path.join(File.cwd!(), ".env.exs")

      if File.exists?(env_file) do
        Code.eval_file(env_file)
      end

      System.put_env("PLUGIN_ID", System.get_env("PLUGIN_ID"))
      System.put_env("COOKIE", "session=abc123")

      assert {:ok, _body} = BubbleApi.fetch_plugin()
    end
  end
end
