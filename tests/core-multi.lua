local test = TEST or require "u-test"
local new_test_env = require "common.test-env"


-- multiple modules tests

test["core - multi module - automatic start"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["multi"] = {
                sourcePath = "assets/services/multi-module.hjson",
            },
        },
        assets = {
            ["scripts/date.lua"] = "assets/scripts/date.lua",
            ["scripts/one-time.lua"] = "assets/scripts/one-time.lua",
        }
    }
    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l")
            if line and line:match("multi started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        -- check log exists
        local logDir = env:get_log_dir()
        local logFile = path.combine(logDir, "multi/default.log")
        while true do
            local logContent = fs.read_file(logFile)
            if logContent and logContent:match("date:") and logContent:match("service start") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not write to log in time"
            end
        end
        return true
    end):run(function()
        return true -- some other test if needed
    end):result()
    test.assert(result, err)
end

test["core - multi module - stop"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["multi"] = {
                sourcePath = "assets/services/multi-module.hjson",
            },
        },
        assets = {
            ["scripts/date.lua"] = "assets/scripts/date.lua",
            ["scripts/one-time.lua"] = "assets/scripts/one-time.lua",
        }
    }

    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l")
            if line and line:match("multi started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        -- stop the service
        local ok, outputOrError = env:asctl({ "stop", "multi" })
        if not ok then
            return false, outputOrError
        end

        while true do -- wait for service stopped
            local line = ascendOutput:read("l")
            if line and line:match("multi stopped") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not stop in time"
            end
        end

        return true
    end):result()
    test.assert(result, err)
end

if not TEST then
    test.summary()
end
