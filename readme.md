# Ascend Service Manager
Ascend is a lightweight and portable service manager built on the [eli](https://github.com/alis-is/eli) Lua-based framework. It efficiently manages application services and is open-source under the AGPL-3.0 license.

## Features
* Lightweight and portable
* Built on the [eli](https://github.com/alis-is/eli) Lua-based framework
* Open-source under the AGPL-3.0 license

## Prerequisites
* Unix-based operating system
* [eli](https://github.com/alis-is/eli) framework installed
* Basic knowledge of command-line operations

## Installation
#### 1. Install [ascend](https://github.com/alis-is/ascend):

Ascend relies on the [eli](https://github.com/alis-is/eli) framework. To install the latest binary release of [ascend](https://github.com/alis-is/ascend), run:

```bash
wget https://raw.githubusercontent.com/alis-is/ascend/main/tools/setup/standalone-linux.sh -O /tmp/setup-ascend.sh && sh /tmp/setup-ascend.sh
```
This command downloads and executes the installation script for `ascend`, `asctl` and `eli` and setup the path for them.
If needed please use `sudo`

#### 2. Configuration
Ascend utilizes environment variables for its configuration. You can override the default settings by setting the following environment variables:

* `ASCEND_SERVICES`: Path to the services directory.
* `ASCEND_HEALTHCHECKS`: Path to the health checks directory.
* `ASCEND_SOCKET`: Path to the IPC endpoint socket.
* `ASCEND_LOGS`: Path to the log directory.
* `ASCEND_INIT`: Path to the initialization script.

To set these environment variables in a Unix-based system, use the `export` command:
```bash
export ASCEND_SERVICES=/path/to/your/services
export ASCEND_HEALTHCHECKS=/path/to/your/healthchecks
export ASCEND_SOCKET=/path/to/your/socket
export ASCEND_LOGS=/path/to/your/logs
export ASCEND_INIT=/path/to/your/init_script
```
Replace `/path/to/your/...` with the actual paths you intend to use.

## Service Definition Reference

Ascend reads `.hjson` service definitions from `ASCEND_SERVICES`. A service can be defined either as a single module:

```hjson
{
	executable: "eli"
	args: ["/opt/example/date.lua"]
}
```

or as a multi-module service:

```hjson
{
	autostart: true
	restart: "on-exit"
	modules: {
		api: {
			executable: "eli"
			args: ["/opt/example/api.lua"]
		}
		worker: {
			executable: "eli"
			args: ["/opt/example/worker.lua"]
			restart: "always"
		}
	}
}
```

Supported fields:

* `executable` (`string`, required per module): command to run.
* `args` (`string[]`, default `[]`): arguments passed to `executable`.
* `environment` (`object`, default `{}`): environment variables for the module process.
* `working_directory` (`string`): working directory used before spawning the process.
* `autostart` (`boolean`, default `true`): start the module during boot.
* `start_delay` (`number`): delay autostart by N seconds.
* `restart` (`"always" | "never" | "on-failure" | "on-success" | "on-exit"`, default `"on-exit"`): restart policy.
* `restart_delay` (`number`, default `1`): delay before an automatic restart.
* `restart_max_retries` (`number`, default `5`): maximum automatic restart attempts when the policy is not `always`.
* `stop_signal` (`number`, default `SIGTERM`): signal sent during shutdown.
* `stop_timeout` (`number`, default `10`): seconds to wait before forcing `SIGKILL`.
* `user` (`string`): Unix user used to spawn the process when supported by the platform.
* `log_file` (`string | "none"`, default `<service>/<module>.log`): relative paths are resolved under `ASCEND_LOGS`; use `"none"` to inherit stdout/stderr instead of capturing logs to files.
* `log_rotate` (`boolean`, default `true`): enable rotation for file-backed logs.
* `log_max_size` (`number|string`, default `10m`): maximum log file size before rotation; `k`, `m`, and `g` suffixes are accepted.
* `log_max_files` (`number`, default `5`): number of rotated files to keep; `0` disables on-disk log retention.
* `depends` (`string[]`): dependencies that must be active before the module starts. Bare names resolve to modules in the same service first and otherwise to whole services. Use `service:module` to depend on a specific external module.
* `healthcheck` (`object`): optional health check definition with fields:
	* `name` (`string`): executable inside `ASCEND_HEALTHCHECKS`.
	* `interval` (`number`, default `30`): seconds between checks.
	* `timeout` (`number`, default `30`): maximum runtime per check.
	* `retries` (`number`, default `1`): consecutive failing checks before the module becomes unhealthy.
	* `delay` (`number`, default `30`): wait time after process start before health checks begin.
	* `action` (`"restart" | "none"`, default `"none"`): action taken when the module becomes unhealthy.

Notes:

* If `modules` is omitted, Ascend creates a single module named `default`.
* When you start a module or service, Ascend starts its dependencies first. During boot, dependents wait in `to-be-started` state until their dependencies become active.
* When you explicitly stop a dependency, Ascend stops its dependents before stopping the dependency itself.

## Usage
### 1. Start Ascend:

Execute [ascend](https://github.com/alis-is/ascend):

```bash
ascend
```
Ascend will read the environment variables and manage the defined services accordingly.

### 2. Manage Services:

* #### Start a Service:
```bash
asctl start <service-name>
```

* #### Stop a Service:
```bash
asctl stop <service-name>
```

* #### Restart a Service:
```bash
asctl restart <service-name>
```

* #### List all running services:
```bash
asctl list
```

* #### Check Service Status:
```bash
asctl status <service-name>
```

* #### Check Service Configuration:
```bash
asctl show <service-name>
```

* #### Show Service Definition File:
```bash
asctl cat <service-name>
```

* #### Read Service Logs:
```bash
asctl logs <service-name>
```

* #### Follow Service Logs:
```bash
asctl logs <service-name> -f
```
Replace `<service-name>` with the name of your service.

### 3. Timeouts

Both `ascend` and `asctl` accept timeout values as plain seconds or with `s`, `m`, or `h` suffixes.

```bash
ascend --timeout=10m
asctl status <service-name> --timeout=5s
asctl logs <service-name> -f --timeout=30s
```

For `asctl`, `--timeout` limits the control request duration. For `asctl logs`, it also limits how long log streaming runs. Without `-f`, `asctl logs` prints a short snapshot and exits.

`asctl cat` prints the raw `.hjson` service definition. When you request more than one service, it prefixes each definition with its source path so the output stays readable.

### 4. CLI Output and Exit Codes

`asctl list`, `asctl status`, and `asctl show` automatically adapt their output:

* When stdout is a TTY, they render human-friendly tables or structured blocks.
* When stdout is piped or redirected, they emit compact JSON suitable for scripts.

Example:

```bash
asctl status <service-name> | jq
```

`asctl` uses distinct exit codes so automation can tell transport failures from command failures:

* `0`: success.
* `20`: JSON-RPC or transport error.
* `21`: command failed after the request was accepted.

## Logging
Ascend logs service output under `ASCEND_LOGS`. By default each module writes to `ASCEND_LOGS/<service-name>/<module-name>.log`.

Use `asctl logs <service-name>` to read current output and `asctl logs <service-name> -f` to follow log output. The same timeout syntax described above applies to log reads and follow sessions.

## License
This project is licensed under the AGPL-3.0 License. See the [LICENSE](LICENSE) file for details.

_Note: Ensure you have the necessary permissions to execute scripts and manage services on your system_



#### Sample run

#### 1. Clone the Ascend Repository:

```bash
git clone https://github.com/alis-is/ascend.git
```
#### 2. Navigate to the Ascend source directory and setup env variables:

```bash
cd ascend/src
export ASCEND_SERVICES=../tests/assets/services/1
export ASCEND_LOGS=../logs
```

#### 3. Start ascend with trace log-level:
```bash
ascend --log-level=trace
```

#### 4. Ascend control commands:

In another terminal u can run the `asctl` commands to check the running service.
