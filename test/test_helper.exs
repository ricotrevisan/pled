ExUnit.start()

defmodule Pled.TestAdapter do
  @moduledoc """
  Req request adapter for tests.

  Req 0.7 deprecated `adapter: fun` in favour of `adapter: mod`, so tests
  configure `adapter: Pled.TestAdapter` and pass the request handler function
  via application env:

      Application.put_env(:pled, :req_options, adapter: Pled.TestAdapter)

      Application.put_env(:pled, :test_adapter_fun, fn request ->
        {request, %Req.Response{status: 200, body: %{}}}
      end)
  """

  def run(%Req.Request{} = request) do
    case Application.get_env(:pled, :test_adapter_fun) do
      fun when is_function(fun, 1) ->
        fun.(request)

      _ ->
        raise "Pled.TestAdapter requires a 1-arity function in " <>
                "Application env :pled, :test_adapter_fun"
    end
  end
end
