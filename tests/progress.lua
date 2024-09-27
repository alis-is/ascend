local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

test["core - single module - working_directory"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-date.hjson",
                definition = {
                    working_directory = "environments",

                }
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

        return os.cwd():match("environments")
    end):result()
    test.assert(result, err)
end
