local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

test["core - single module - restart on-success"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["one"] = {
                sourcePath = "assets/services/simple-one-time.hjson",
                definition = {
                    restart = "on-success",
                }
            },
        },
        assets = {
            ["scripts/one-time.lua"] = "assets/scripts/one-time.lua",
        }
    }

    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()


        while true do
            print(ascendOutput:read("l"))
        end

        while true do -- wait for service started
            local line = ascendOutput:read("l")
            if line and line:match("one started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        while true do -- wait for service exists
            local line = ascendOutput:read("l")
            if line and line:match("one:default exited with code 0") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not stop in time"
            end
        end

        while true do -- wait for service to restart
            local line = ascendOutput:read("l")
            if line and line:match("restarting one") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not restart in time"
            end
        end

        return true
    end):result()
    test.assert(result, err)
end
