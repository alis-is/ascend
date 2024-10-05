local test = TEST or require "u-test"
local new_test_env = require "common.test-env"


local function exec_command(command)
    local output = io.popen(command)
    if not output then
        return nil
    end
    local result = output:read("l")
    output:close()
    return result
end

local function is_windows()
    return package.config:sub(1, 1) == "\\"
end


test["isolation - user"] = function()
    if is_windows() then
        print("Test skipped: Not supported on Windows")
        return
    end

    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-date.hjson",

            }
        },
        assets = {
            ["scripts/date.lua"] = "assets/scripts/date.lua"
        }
    }
    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l", 2)
            if line and line:match("date:default started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        local psOutput = exec_command("ps aux | grep /assets/scripts/date.lua")
        if not psOutput then
            return false, "Failed to get process list"
        end
        local userName = psOutput:match("^(%S+)")
        local whoamiOutput = exec_command("whoami")

        return userName == whoamiOutput
    end):result()
    test.assert(result, err)
end

test["isolation - ascend slice"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-date.hjson",
            }
        },
        assets = {
            ["scripts/date.lua"] = "assets/scripts/date.lua"
        }
    }

    local first_env_dir = ""
    local second_env_dir = ""

    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l", 2)
            if line and line:match("date:default started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        first_env_dir = env:get_path()
        return true
    end):result()

    local result2, err2 = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l", 2)
            if line and line:match("date:default started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        second_env_dir = env:get_path()
        return true
    end)
    test.assert(result, err)
    test.assert(result2, err2)
    test.assert(first_env_dir ~= second_env_dir, "slice isolation failed")
end
