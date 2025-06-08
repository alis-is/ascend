local trace, warn = util.global_log_factory("plugin/asctl", "trace", "warn")
local hjson = require"hjson"

assert(os.execute('asctl --version 2>&1 >/dev/null'), "asctl not found")
assert(proc.EPROC, "asctl plugin requires posix proc extra api (eli.proc.extra)")

local ASCEND_SERVICES = os.getenv("ASCEND_SERVICES") or "/etc/ascend/services"

local asctl = {}

function asctl.exec(...)
    local cmd = string.join_strings(" ", ...)
    trace("Executing asctl " .. cmd)
    local process = proc.spawn("asctl", { ... }, { stdio = { stdout = "pipe", stderr = "pipe" }, wait = true }) --[[@as SpawnResult]]
    if not process then
        error("Failed to execute asctl command: " .. cmd)
    end
    trace("asctl exit code: " .. process.exit_code)

    local stderr = process.stderr_stream:read("a")
    local stdout = process.stdout_stream:read("a")
    return process.exit_code, stdout, stderr
end

function asctl.with_options(options)
    warn("options are not supported by asctl right now")
    return asctl
end

function asctl.install_service(sourceFile, serviceName, options)
    if type(options) ~= "table" then
        options = {}
    end
    if type(options.kind) ~= "string" then
        options.kind = "service"
    end
    local serviceUnitFile = string.interpolate("${service_directory}/${service}.hjson", {
        service_directory = ASCEND_SERVICES,
        service = serviceName
    })
    local ok, err = fs.copy_file(sourceFile, serviceUnitFile)
    assert(ok, string.interpolate("Failed to install ${service} (${file}): ${error}", {
        service = serviceName,
        file = serviceUnitFile,
        error = err
    }))

    if type(options.reload) ~= "boolean" or options.reload == true then
        local _exit_code, _stdout, _stderr = asctl.exec("reload")
        if _exit_code ~= 0 then
            warn({ msg = "Failed to reload ascend daemon!", stdout = _stdout, stderr = _stderr })
        end
    end
end

function asctl.start_service(service_name)
    trace("Starting service: ${service}", { service = service_name })
    local exit_code = asctl.exec("start", service_name)
    assert(exit_code == 0, "Failed to start service")
    trace("Service ${service} started.", { service = service_name })
end

function asctl.stop_service(service_name)
    trace("Stoping service: ${service}", { service = service_name })
    local exit_code = asctl.exec("stop", service_name)
    assert(exit_code == 0, "Failed to stop service")
    trace("Service ${service} stopped.", { service = service_name })
end

function asctl.remove_service(service_name, options)
    if type(options) ~= "table" then
        options = {}
    end
    local serviceUnitFile = string.interpolate("${service_directory}/${service}.hjson", {
        service_directory = ASCEND_SERVICES,
        service = service_name
    })
    if not fs.exists(serviceUnitFile) then return end -- service not found so skip

    trace("Removing service: ${service}", { service = service_name })
    local exit_code = asctl.exec("stop", service_name)
    assert(exit_code == 0, "Failed to stop service")
    trace("Service ${service} stopped.", { service = service_name })

    trace("Removing service...")
    local ok, err = fs.remove(serviceUnitFile)
    if not ok then
        error(string.interpolate("Failed to remove ${service} (${file}): ${error}", {
            service = service_name,
            file = serviceUnitFile,
            error = err
        }))
    end

    if type(options.reload) ~= "boolean" or options.reload == true then
        local exit_code, stdout, stderr = asctl.exec("reload")
        if exit_code ~= 0 then
            warn({ msg = "Failed to reload ascend!", stdout = stdout, stderr = stderr })
        end
    end
    trace("Service ${service} removed.", { service = service_name })
end

function asctl.get_service_status(serviceName)
    trace("Getting service " .. serviceName .. "status...")
    local exit_code, stdout = asctl.exec("status", serviceName)
    assert(exit_code == 0, "Failed to get service status")
    local response = hjson.parse(stdout) --[[@as table<string, { ok: boolean, status: table<string, AscendManagedServiceModuleStatus> }>]]
    local serviceStatus = response[serviceName].status
    local moduleStatus = serviceStatus.default
    if type(serviceStatus) ~= "table" then
        error("Failed to get service status")
    end
    local status = moduleStatus.state == "active" and "running" or "stopped"
    local started = moduleStatus.started and os.date("%a %Y-%m-%d %H:%M:%S", moduleStatus.started)
    return status, started
end

return asctl
