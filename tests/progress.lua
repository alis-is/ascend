local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

test["asctl - restart"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                sourcePath = "assets/services/simple-date.hjson",
            }
        },
        assets = {
            ["scripts/date.lua"] = "assets/scripts/date.lua"
        }
    }

    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l")
            if line and line:match("date started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        -- stop the service
        local ok, outputOrError = env:asctl({ "restart", "date" })
        if not ok then
            return false, outputOrError
        end

        local steps = 0 -- at 2 steps we consider test completed (stop + start)
        while true do   -- wait for service stopped
            local line = ascendOutput:read("l")
            if line and (line:match("date stopped") or line:match("date started")) then
                steps = steps + 1
            end
            if steps == 2 then
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
