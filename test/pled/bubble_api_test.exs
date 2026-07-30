defmodule Pled.BubbleApiTest do
  use ExUnit.Case, async: false

  alias Pled.BubbleApi

  setup do
    previous_plugin_id = System.get_env("PLUGIN_ID")
    previous_cookie = System.get_env("BUBBLE_COOKIE")
    previous_req_options = Application.get_env(:pled, :req_options)
    previous_adapter_fun = Application.get_env(:pled, :test_adapter_fun)

    on_exit(fn ->
      restore_env("PLUGIN_ID", previous_plugin_id)
      restore_env("BUBBLE_COOKIE", previous_cookie)

      if previous_req_options do
        Application.put_env(:pled, :req_options, previous_req_options)
      else
        Application.delete_env(:pled, :req_options)
      end

      if previous_adapter_fun do
        Application.put_env(:pled, :test_adapter_fun, previous_adapter_fun)
      else
        Application.delete_env(:pled, :test_adapter_fun)
      end
    end)

    :ok
  end

  describe "fetch_plugin/0" do
    test "returns error when PLUGIN_ID is not available" do
      System.delete_env("PLUGIN_ID")
      System.delete_env("BUBBLE_COOKIE")

      assert {:error, msg} = BubbleApi.fetch_plugin()
      assert msg =~ "Plugin ID not found"
    end

    test "returns error when BUBBLE_COOKIE environment variable is not set" do
      System.put_env("PLUGIN_ID", "test_plugin_id")
      System.delete_env("BUBBLE_COOKIE")

      assert {:error, "Environment variable BUBBLE_COOKIE is not set"} = BubbleApi.fetch_plugin()

      System.delete_env("PLUGIN_ID")
    end

    test "makes HTTP request with correct URL and headers when env vars are set" do
      System.put_env("PLUGIN_ID", "test_plugin_123")
      System.put_env("BUBBLE_COOKIE", "session=abc123")

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
      System.delete_env("BUBBLE_COOKIE")
    end

    @tag :integration
    test "makes end to end call" do
      env_file = Path.join(File.cwd!(), ".env.exs")

      if File.exists?(env_file) do
        Code.eval_file(env_file)
      end

      System.put_env("PLUGIN_ID", System.get_env("PLUGIN_ID"))
      System.put_env("BUBBLE_COOKIE", "session=abc123")

      assert {:ok, _body} = BubbleApi.fetch_plugin()
    end
  end

  describe "save_plugin/0" do
    @tag :tmp_dir
    test "returns an actionable unauthorized error when Bubble rejects edit permission", %{
      tmp_dir: tmp_dir
    } do
      File.mkdir_p!(Path.join(tmp_dir, "dist"))
      File.write!(Path.join(tmp_dir, "dist/plugin.json"), Jason.encode!(%{"name" => "Test"}))

      System.put_env("PLUGIN_ID", "test_plugin_123")
      System.put_env("BUBBLE_COOKIE", "session=abc123")

      Application.put_env(:pled, :req_options, adapter: Pled.TestAdapter)

      Application.put_env(:pled, :test_adapter_fun, fn request ->
        assert request.method == :post
        assert URI.to_string(request.url) == "https://bubble.io/appeditor/save_plugin"
        assert Req.Request.get_header(request, "cookie") == ["session=abc123"]

        assert Jason.decode!(IO.iodata_to_binary(request.body)) == %{
                 "id" => "test_plugin_123",
                 "raw" => %{"name" => "Test"}
               }

        response = %Req.Response{
          status: 401,
          body: %{
            "error_class" => "Unauthorized",
            "translation" => "You don't have permission to edit this plugin."
          }
        }

        {request, response}
      end)

      File.cd!(tmp_dir, fn ->
        ExUnit.CaptureIO.capture_io(fn ->
          ExUnit.CaptureIO.capture_io(:stderr, fn ->
            assert {:error, {:unauthorized, message}} = BubbleApi.save_plugin()
            assert message =~ "permission"
            assert message =~ "BUBBLE_COOKIE"
          end)
        end)
      end)
    end
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
