local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

test["asctl - status"] = function()
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

        local ok, outputOrError = env:asctl({ "status", "date" })
        if not ok then
            return false, outputOrError
        end

        local output = outputOrError
        return output:match("date") and output:match("status") and output:match('"ok":true')
    end):result()
    test.assert(result, err)
end
