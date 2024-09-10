---@class AscendTestEnvOptions
---@field services table<string, string>?
---@field healthchecks table<string, string>?
---@field vars table<string, table<string,string>>?


---@class AscendTestEnv
---@field private path string
---@field private is_open boolean
---@field private options AscendTestEnvOptions
---@field run fun(self: AscendTestEnv, test: fun(): boolean, string?): boolean, string?

local function random_string(length)
    local charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local result = ""
    for i = 1, length do
        local randIndex = math.random(1, #charset)
        result = result .. charset:sub(randIndex, randIndex)
    end
    return result
end


local AscendTestEnv = {}
AscendTestEnv.__index = AscendTestEnv

---@param options AscendTestEnvOptions
---@return AscendTestEnv
function AscendTestEnv:new(options)
    local obj = setmetatable({}, AscendTestEnv)
    local testId = random_string(8)
    obj.path = path.combine("tmp", testId)
    obj.is_open = true
    obj.options = options

    local ok = fs.safe_mkdirp(obj.path)
    if not ok then
        error("Failed to create test directory")
    end

    local serviceDir = path.combine(obj.path, "services")
    fs.mkdirp(serviceDir)
    fs.mkdirp(path.combine(obj.path, "logs"))
    fs.mkdirp(path.combine(obj.path, "healthchecks"))

    for serviceName, serviceSource in pairs(options.services) do
        local content = fs.read_file(serviceSource)
        if not content then
            error("Failed to read service source")
        end
        fs.write_file(path.combine(serviceDir, serviceName .. ".hjson"), string.interpolate(content, options.vars[serviceName]))
    end

    --  TODO: finish ascend config, env etc.
    return obj
end

---@param test fun(): boolean, string
function AscendTestEnv:run(test)
    if not self.is_open then
        return false, "Test environment is closed"
    end
    -- TODO: run ascend
    --- local ascendProcess, err = proc.spawn("eli", { "../src/ascend/lua", "--log-level=trace"}, {  })
    --- ...
    local result = test()
    --- ascendProcess:kill()
    return result
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