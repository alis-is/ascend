local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

test["core - multi module - stop only one module"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["multi"] = {
                source_path = "assets/services/multi-module.hjson",
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
            local line = ascendOutput:read("l", 2)
            if line and line:match("multi:date started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        -- stop the service
        local ok, outputOrError = env:asctl({ "stop", "multi:one" })
        if not ok then
            return false, outputOrError
        end

        local stopTime = os.time()
        local oneStopped = false
        while true do -- wait for service stopped
            local line = ascendOutput:read("l", 1)
            if line and line:match("multi:date stopped") then
                oneStopped = true
            end

            if line and line:match("multi:date stopped") then
                return false, 'Wrong module stopped'
            end

            if os.time() > stopTime + 5 then
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
