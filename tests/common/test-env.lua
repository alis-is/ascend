local hjson = require "hjson"
local enter_dir = require "common.working-dir"

---@class AscendTestEnvServiceDefinition
---@field sourcePath string?
--- NOTE: you want to check ./src/ascend/internals/env.lua:22 for available options
---@field definition table<string, any>? -- if we only have parial

---@class AscendTestEnvOptions
---@field services table<string, AscendTestEnvServiceDefinition>?
---@field healthchecks table<string, string>?
---@field vars table<string, table<string,string>>?
---@field assets table<string, string>?
---@field init string?


---@class AscendTestEnv
---@field private path string
---@field private is_open boolean
---@field private options AscendTestEnvOptions
---@field private error string?
---@field private init string?
---@field private vars table<string, table<string,string>>?
---@field private serviceDir string?
---@field private logDir string?
---@field private assetsDir string?
---@field private build_env fun(self: AscendTestEnv): table<string, string>
---@field update_env fun(self: AscendTestEnv, options: AscendTestEnvOptions): boolean, string
---@field run fun(self: AscendTestEnv, test: fun(env: AscendTestEnv, ascendOutput: EliReadableStream): boolean, string?): AscendTestEnv
---@field result fun(self: AscendTestEnv): boolean, string?
---@field get_service_dir fun(self: AscendTestEnv): string
---@field get_log_dir fun(self: AscendTestEnv): string
---@field get_assets_dir fun(self: AscendTestEnv): string
---@field asctl fun(self: AscendTestEnv, args: string[], timeout: number?): boolean, string

---@param definition table<string, any>
---@param envPath string
local function patch_definition(definition, envPath)
    for key, value in pairs(definition) do
        if type(value) == "table" then
            definition[key] = patch_definition(value, envPath)
        end
        if key == "working_dir" then
            definition[key] = path.combine(envPath, value)
        end
    end
    return definition
end



local AscendTestEnv = {}
AscendTestEnv.__index = AscendTestEnv

---@param options AscendTestEnvOptions
function AscendTestEnv:update_env(options)
    for serviceName, serviceDefinition in pairs(options.services) do
        local base = {}
        if serviceDefinition.sourcePath then
            local content = fs.read_file(serviceDefinition.sourcePath)
            if not content then
                return false, "Failed to read service source for " .. serviceName
            end
            local ok, decodedOrError = pcall(hjson.decode, content)
            if not ok then
                return false, decodedOrError
            end
            base = decodedOrError
        end

        local definition = util.merge_tables(base, serviceDefinition.definition, {
            overwrite = true,
            arrayMergeStrategy = "prefer-t2",
        })
        local encodedDefinition = hjson.encode(patch_definition(definition, self.path))
        encodedDefinition = string.interpolate(encodedDefinition, self.vars)
        fs.write_file(path.combine(self.serviceDir, serviceName .. ".hjson"), encodedDefinition)
    end

    for assetDestination, assetSourcePath in pairs(options.assets) do
        assetDestination = path.combine(self.assetsDir, assetDestination)
        local dir = path.dir(assetDestination)
        fs.mkdirp(dir)
        local copySuccess = fs.copy(assetSourcePath, assetDestination)
        if not copySuccess then
            return false, "Failed to copy asset: " .. assetSourcePath
        end
    end

    return true
end

---@param options AscendTestEnvOptions
---@return AscendTestEnv
function AscendTestEnv:new(options)
    local obj = setmetatable({}, AscendTestEnv)
    local testId = util.random_string(8)
    obj.path = path.combine("tmp", testId)
    if obj.path and not path.isabs(obj.path) then
        obj.path = path.combine(os.cwd(), obj.path)
    end

    obj.is_open = true
    obj.options = options
    obj.init = options.init
    if obj.init and not path.isabs(obj.init) then
        obj.init = path.combine(obj.path, obj.init)
    end

    local ok = fs.safe_mkdirp(obj.path)
    if not ok then
        obj.error = "Failed to create test directory"
        return obj
    end

    obj.serviceDir = path.combine(obj.path, "services")
    fs.mkdirp(obj.serviceDir)
    obj.logDir = path.combine(obj.path, "logs")
    fs.mkdirp(obj.logDir)
    fs.mkdirp(path.combine(obj.path, "healthchecks"))
    obj.assetsDir = path.combine(obj.path, "assets")
    fs.mkdirp(obj.assetsDir)

    obj.vars = util.merge_tables(options.vars, {
        INTERPRETER = INTERPRETER,
        ENV_DIR = obj.path
    })

    local ok, err = obj:update_env(options)
    if not ok then
        obj.error = err
        return obj
    end

    --  TODO: finish ascend config, env etc.
    return obj
end

function AscendTestEnv:build_env(env)
    return {
        HOME = self.path,
        ASCEND_SERVICES = path.combine(self.path, "services"),
        ASCEND_LOGS = path.combine(self.path, "logs"),
        ASCEND_APPS = path.combine(self.path, "apps"),
        ASCEND_HEALTHCHECKS = path.combine(self.path, "healthchecks"),
        ASCEND_INIT = self.init and path.combine(self.path, "init.lua"),
        ASCEND_SOCKET = path.combine(self.path, "ascend.sock"),
        APPS_BOOTSTRAP = path.combine(self.path, "apps-bootstrap"),
        PATH = os.getenv("PATH") or "",
    }
end

---@param test fun(env: AscendTestEnv, ascendOutputStream: EliReadableStream): boolean, string
function AscendTestEnv:run(test)
    if self.error then
        return false, self.error
    end

    if not self.is_open then
        return false, "Test environment is closed"
    end

    local srcDir <close> = enter_dir("../src")
    local ascendProcess, err = proc.spawn(INTERPRETER, { "ascend.lua", "--log-level=trace" }, {
        stdio = {
            output = "pipe",
        },
        env = self:build_env(),
        -- wait = true,
    })

    if not ascendProcess then
        self.error = err
        return self
    end

    local readableStream = ascendProcess:get_stdout()
    if not readableStream then
        self.error = "Failed to get stdout"
        return self
    end

    local ok, err = test(self, readableStream)

    if not ok then
        self.error = err or "test error"
    end

    ascendProcess:kill()
    ascendProcess:wait()
    return self
end

function AscendTestEnv:get_service_dir()
    return self.serviceDir
end

function AscendTestEnv:get_log_dir()
    return self.logDir
end

function AscendTestEnv:get_assets_dir()
    return self.assetsDir
end

function AscendTestEnv:asctl(args, timeout)
    local srcDir <close> = not fs.exists("asctl.lua") and enter_dir("src") or nil
    args = util.merge_arrays({ "asctl.lua" }, args)
    local asctlProcess, err = proc.spawn(INTERPRETER, args, {
        stdio = { output = "pipe" },
        env = self:build_env(),
    })
    if not asctlProcess then
        return false, err
    end

    local output = asctlProcess:get_stdout()
    if not output then
        return false, "failed to get stdout"
    end

    local exitCode = asctlProcess:wait(timeout)
    return exitCode == 0, output:read("a")
end

function AscendTestEnv:result()
    if self.error then
        return false, self.error
    end

    return true
end

-- Close method
function AscendTestEnv:__close()
    if DISABLE_CLEANUP then
        return
    end
    if self.is_open then
        self.is_open = false
        fs.remove(self.path, { recurse = true })
    end
end

AscendTestEnv.__gc = AscendTestEnv.__close

return function(options)
    return AscendTestEnv:new(options)
end
