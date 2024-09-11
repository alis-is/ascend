---@class AscendTestEnvOptions
---@field services table<string, string>?
---@field healthchecks table<string, string>?
---@field vars table<string, table<string,string>>?


---@class AscendTestEnv
---@field private path string
---@field private is_open boolean
---@field private options AscendTestEnvOptions
---@field private error string?
---@field run fun(self: AscendTestEnv, test: fun(): boolean, string?): AscendTestEnv
---@field result fun(self: AscendTestEnv): boolean, string?

local AscendTestEnv = {}
AscendTestEnv.__index = AscendTestEnv

---@param options AscendTestEnvOptions
---@return AscendTestEnv
function AscendTestEnv:new(options)
    local obj = setmetatable({}, AscendTestEnv)
    local testId = util.random_string(8)
    obj.path = path.combine("tmp", testId)
    obj.is_open = true
    obj.options = options

    local ok = fs.safe_mkdirp(obj.path)
    if not ok then
        obj.failed = "Failed to create test directory"
        return obj
    end

    local serviceDir = path.combine(obj.path, "services")
    fs.mkdirp(serviceDir)
    fs.mkdirp(path.combine(obj.path, "logs"))
    fs.mkdirp(path.combine(obj.path, "healthchecks"))

    for serviceName, serviceSource in pairs(options.services) do
        local content = fs.read_file(serviceSource)
        if not content then
            obj.failed = "Failed to read service source"
            return obj
        end
        fs.write_file(path.combine(serviceDir, serviceName .. ".hjson"), string.interpolate(content, options.vars[serviceName]))
    end

    --  TODO: finish ascend config, env etc.
    return obj
end

---@param test fun(): boolean, string
function AscendTestEnv:run(test)
    if self.failed then
        return false, self.failed
    end

    if not self.is_open then
        return false, "Test environment is closed"
    end
    -- TODO: run ascend
    --- local ascendProcess, err = proc.spawn("eli", { "../src/ascend/lua", "--log-level=trace"}, {  })
    --- ...
    local result = test()
    --- ascendProcess:kill()
    return self
end

function AscendTestEnv:result()
    if self.failed then
        return false, self.failed
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