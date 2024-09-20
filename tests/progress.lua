local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

test["core - multi module - restart on-exit"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["multi"] = {
                sourcePath = "assets/services/multi-module-ending.hjson",
                definition = {
                    restart = "on-exit",
                    restart_max_retries = 2,
                }
            },
        },
        assets = {
            ["scripts/one-time.lua"] = "assets/scripts/one-time.lua",
            ["scripts/one-time2.lua"] = "assets/scripts/one-time2.lua",
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

        while true do -- wait for service exists
            local line = ascendOutput:read("l")
            if line and line:match("multi:one2 exited with code 0") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not stop in time"
            end
        end

        local stopTime = os.time()
        local retries = 0
        while true do -- wait for service to restart
            local line = ascendOutput:read("l", 2, "s")
            if line and line:match("restarting multi:one2") then
                retries = retries + 1
            end

            if retries > 2 then
                return false, "Service did not respect restart_max_retries. Restarted more times."
            end

            if os.time() > stopTime + 10 then
                break
            end
        end

        if retries < 2 then
            return false, "Service did not respect restart_max_retries. Restarted less times."
        end

        return true
    end):result()
    test.assert(result, err)
end
