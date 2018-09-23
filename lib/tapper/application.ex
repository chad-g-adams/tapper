defmodule Tapper.Application do
  @moduledoc """
  Tapper main application; configures and starts application supervisor.

  Automatically started when Tapper is included as dependency.

  ## Configuration

  Looks for configuration under `:tapper` key:

  | key         | type     | purpose |
  | --          | --       | --      |
  | `system_id` | `String.t` | This application's id; used for `service_name` in default [`Endpoint`](Tapper.Endpoint.html) used in annotations; default `unknown` |
  | `ip`        | `tuple`    | This application's principle IPV4 or IPV6 address, as 4- or 8-tuple of ints; defaults to IP of first non-loopback interface, or `{127.0.0.1}` if none. |
  | `port`      | `integer`  | The application's principle port, e.g. HTTP port 80; defaults to 0 |
  | `reporter`  | `atom` | `{atom, any}` | `function/1` | Module implementing `Tapper.Reporter.Api` <sup>[1]</sup>, or function of arity 1 to use for reporting spans; defaults to `Tapper.Reporter.Console`. |
  | `server_trace` | `atom` | Logger level to log server traces at, or `false` (default `false`) |

  All keys support the Phoenix-style `{:system, var}` format<sup>[2]</sup>, to allow lookup from shell environment variables, e.g. `{:system, "PORT"}` to read `PORT` environment variable.

  Config values will be converted to the expected type, principally so that string values can be handled from environment variables:
  *  `ip` is expected in dotted IPV4 or colon IPV6 notation, see Erlang's [`inet:parse_address/1`](http://erlang.org/doc/man/inet.html#parse_address-1)
  * `reporter` can be specified as a string which will be converted to an atom, following Elixir's module name rules.

  ## Example
  In `config.exs` etc.:

  ```
  config :tapper,
    system_id: "my-cool-svc",
    reporter: Tapper.Reporter.Zipkin,
    port: {:system, "PORT"}
  ```

  <sup>[1]</sup> If the reporter is given as `{module, arg}` it will be started using the returned
  spec under Tapper's main supervisor; see `Supervisor` module for details  of what the `child_spec/1` function should return.
  <sup>[2]</sup> Tapper uses the [`DeferredConfig`](https://hexdocs.pm/deferred_config/readme.html)
  library to resolve all configuration under the `:tapper` key, so see its documention for more options.

  """

  use Application

  require Logger

  import Tapper.Config

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    DeferredConfig.populate(:tapper)

    reporter = Application.get_env(:tapper, :reporter, Tapper.Reporter.Console)
    {reporter, reporter_spec} = case reporter do
      {module, _args} = spec -> {module, spec}
      module -> {module, nil}
    end

    Tapper.Reporter.ensure_reporter!(reporter)

    config = %{
      host_info: %{
        ip: to_ip(Application.get_env(:tapper, :ip, Tapper.Endpoint.host_ip())),
        port: to_int(Application.get_env(:tapper, :port, 0)),
        system_id: Application.get_env(:tapper, :system_id, "unknown")
      },
      reporter: reporter,
      server_trace: Application.get_env(:tapper, :server_trace, false),
    }

    Logger.info(fn -> "Starting Tapper Application" end)

    # Define workers and child supervisors to be supervised
    children = [
      {Registry, keys: :unique, name: Tapper.Tracers},
      {Tapper.Tracer.Supervisor, config},
    ]

    children =
      if reporter_spec do
        Logger.info(fn -> "Supervising reporter module #{Macro.to_string(config.reporter)}" end)
        [reporter_spec | children]
      else
          children
      end

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Tapper.Supervisor]
    Supervisor.start_link(children, opts)
  end

end
