local trace, warn = util.global_log_factory("plugin/asctl", "trace", "warn")
local hjson = require"hjson"

assert(os.execute('asctl --version 2>&1 >/dev/null'), "asctl not found")
assert(proc.EPROC, "asctl plugin requires posix proc extra api (eli.proc.extra)")

local ASCEND_SERVICES = os.getenv("ASCEND_SERVICES") or "/etc/ascend/services"

local asctl = {}

function asctl.exec(...)
    local cmd = string.join_strings(" ", ...)
    trace("Executing asctl " .. cmd)
    local proc = proc.spawn("asctl", { ... }, { stdio = { stdout = "pipe", stderr = "pipe" }, wait = true }) --[[@as SpawnResult]]
    if not proc then
        error("Failed to execute asctl command: " .. cmd)
    end
    trace("asctl exit code: " .. proc.exit_code)

    local stderr = proc.stderrStream:read("a")
    local stdout = proc.stdoutStream:read("a")
    return proc.exit_code, stdout, stderr
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
    local serviceUnitFile = string.interpolate("${serivceDirectory}/${service}.hjson", {
        serivceDirectory = ASCEND_SERVICES,
        service = serviceName
    })
    local _ok, _error = fs.safe_copy_file(sourceFile, serviceUnitFile)
    assert(_ok, string.interpolate("Failed to install ${service} (${file}): ${error}", {
        service = serviceName,
        file = serviceUnitFile,
        error = _error
    }))

    if type(options.reload) ~= "boolean" or options.reload == true then
        local _exit_code, _stdout, _stderr = asctl.exec("reload")
        if _exit_code ~= 0 then
            warn({ msg = "Failed to reload ascend daemon!", stdout = _stdout, stderr = _stderr })
        end
    end
end

function asctl.start_service(serviceName)
    trace("Starting service: ${service}", { service = serviceName })
    local exit_code = asctl.exec("start", serviceName)
    assert(exit_code == 0, "Failed to start service")
    trace("Service ${service} started.", { service = serviceName })
end

function asctl.stop_service(serviceName)
    trace("Stoping service: ${service}", { service = serviceName })
    local exit_code = asctl.exec("stop", serviceName)
    assert(exit_code == 0, "Failed to stop service")
    trace("Service ${service} stopped.", { service = serviceName })
end

function asctl.remove_service(serviceName, options)
    if type(options) ~= "table" then
        options = {}
    end
    local serviceUnitFile = string.interpolate("${serivceDirectory}/${service}.hjson", {
        serivceDirectory = ASCEND_SERVICES,
        service = serviceName
    })
    if not fs.exists(serviceUnitFile) then return end -- service not found so skip

    trace("Removing service: ${service}", { service = serviceName })
    local exit_code = asctl.exec("stop", serviceName)
    assert(exit_code == 0, "Failed to stop service")
    trace("Service ${service} stopped.", { service = serviceName })

    trace("Removing service...")
    local ok, error = fs.safe_remove(serviceUnitFile)
    if not ok then
        error(string.interpolate("Failed to remove ${service} (${file}): ${error}", {
            service = serviceName,
            file = serviceUnitFile,
            error = error
        }))
    end

    if type(options.reload) ~= "boolean" or options.reload == true then
        local exit_code, stdout, stderr = asctl.exec("reload")
        if exit_code ~= 0 then
            warn({ msg = "Failed to reload ascend!", stdout = stdout, stderr = stderr })
        end
    end
    trace("Service ${service} removed.", { service = serviceName })
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

return util.generate_safe_functions(asctl)
