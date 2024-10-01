local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

test["health checks - timeout"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-date.hjson",
                definition = {
                    healthcheck = {
                        name = "loop.lua",
                        action = "restart",
                        delay = 0,
                        retries = 3,
                        interval = 1,
                        timeout = 1,
                    }
                }
            }
        },
        assets = {
            ["scripts/date.lua"] = "assets/scripts/date.lua",
        },
        healthchecks = {
            ["loop.lua"] = "assets/healthchecks/loop.lua"
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

        --// TODO: remove after eli 0.34.5 release
        local envpath = env:get_path()
        local healthcheckFile = path.combine(envpath, "healthchecks/loop.lua")
        os.execute("chmod 775 " .. healthcheckFile)
        -- till here

        local ok, outputOrError = env:asctl({ "show", "date" })
        if not ok then
            return false, outputOrError
        end
        print(outputOrError)

        local hjson = require "hjson"
        local output = outputOrError
        local show_result = hjson.decode(output)
        if type(show_result) ~= "table" then
            return false, "failed to decode show result"
        end

        if (show_result.date.default.healthcheck.timeout ~= 1) then
            return false, "Healthcheck setting is not updated correctly"
        end

        while true do
            local line = ascendOutput:read("l", 1)
            print(line)
            if line and line:match("healthcheck for date:default timed out") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not timeout in time"
            end
        end

        return true
    end):result()
    test.assert(result, err)
end
