local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

test["core - multi module - global property propagation down to modules"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["multi"] = {
                source_path = "assets/services/multi-module-property-propagation.hjson",
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

        local ok, outputOrError = env:asctl({ "show", "multi:date" })
        if not ok then
            return false, outputOrError
        end
        local hjson = require "hjson"
        local output = outputOrError
        local show_result = hjson.decode(output)
        if type(show_result) ~= "table" then
            return false, "failed to decode show result"
        end

        return show_result.multi.date.restart_delay == 3 and show_result.multi.date.restart == "always"
    end):result()
    test.assert(result, err)
end
