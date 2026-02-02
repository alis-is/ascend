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
Replace `<service-name>` with the name of your service.

## Logging
Ascend logs service output to files located in the logs directory within the project folder. Each service has its own log file named after the service (e.g., `<service-name>.log`).

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
