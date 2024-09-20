local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

test["asctl - start"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                sourcePath = "assets/services/simple-date.hjson",
                definition = {
                    autostart = false,
                }
            }
        },
        assets = {
            ["scripts/date.lua"] = "assets/scripts/date.lua"
        }
    }

    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        -- while true do
        --     print(ascendOutput:read("l"))
        -- end

        while true do
            local line = ascendOutput:read("l", 1, "s")
            if line and line:match("date started") then
                return false, "Service started automatically"
            end
            if os.time() > startTime + 5 then
                break
            end
        end

        local ok, outputOrError = env:asctl({ "start", "date" })
        if not ok then
            return false, outputOrError
        end

        while true do -- wait for service started
            local line = ascendOutput:read("l")
            if line and line:match("date started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        return true
    end):result()
    test.assert(result, err)
end
