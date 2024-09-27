local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

test["core - multi module - stop timeout (kill)"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["multi"] = {
                source_path = "assets/services/multi-module-ignore-sigterm.hjson",
                definition = {
                    restart = "never",
                }
            }
        },
        assets = {
            ["scripts/date.lua"] = "assets/scripts/date.lua",
            ["scripts/ignore-sigterm.lua"] = "assets/scripts/ignore-sigterm.lua"
        }
    }
    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l", 2)
            if line and line:match("multi:ignoreSigterm started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        -- stop the service
        local ok, outputOrError = env:asctl({ "stop", "multi:ignoreSigterm" })
        if not ok then
            return false, outputOrError
        end

        while true do
            local line = ascendOutput:read("l", 2)
            if line and line:match("multi:ignoreSigterm stopped %(killed%)") then
                break
            end
            if os.time() > startTime + 20 then
                return false, "Service did not stop in time"
            end
        end

        return true
    end):result()
    test.assert(result, err)
end
