local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

test["health checks - action - restart"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-date.hjson",
                definition = {
                    healthcheck = {
                        name = "exit1.lua",
                        action = "restart",
                        delay = 0,
                        retries = 1,
                        interval = 1,
                    }
                }
            }
        },
        assets = {
            ["scripts/date.lua"] = "assets/scripts/date.lua",
        },
        healthchecks = {
            ["exit1.lua"] = "assets/healthchecks/exit1.lua"
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
        local healthcheckFile = path.combine(envpath, "healthchecks/exit1.lua")
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

        if (show_result.date.default.healthcheck.action ~= "restart") then
            return false, "Healthcheck setting is not updated correctly"
        end


        local healthcheckFailed = false
        local serviceRestarted = false
        while true do
            local line = ascendOutput:read("l", 1)
            print(line)
            if line and line:match("healthcheck for date:default failed with exit code 1") then
                healthcheckFailed = true
            end
            if line and line:match("restarting date:default") then
                serviceRestarted = true
            end
            if healthcheckFailed and serviceRestarted then
                break
            end

            if os.time() > startTime + 10 then
                return false, "Service did not passed test in time"
            end
        end

        return true
    end):result()
    test.assert(result, err)
end
