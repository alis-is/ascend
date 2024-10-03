local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

test["advanced - init - shell script"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-date.hjson",
            }
        },
        assets = {
            ["scripts/date.lua"] = "assets/scripts/date.lua",
            ["scripts/ascend-init.lua"] = "assets/scripts/ascend-init.lua"
        },
        environment_variables = {
            ASCEND_INIT = "${ENV_DIR}/assets/scripts/ascend-init.sh"
        },


    }
    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        os.execute('export ASCEND_INIT="tezbox init --setup-services"')
        os.execute("echo $ASCEND_INIT")
        print(os.getenv("ASCEND_INIT"))
        local ascend_init_value = os.getenv("ASCEND_INIT")

        if ascend_init_value then
            print("ASCEND_INIT: " .. ascend_init_value)
        else
            print("ASCEND_INIT is not set.")
        end

        while true do
            print(ascendOutput:read("l", 2))
            os.sleep(1)
        end

        while true do -- wait for service started
            local line = ascendOutput:read("l", 2)
            if line and line:match("date:default started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

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

        if (show_result.date.default.healthcheck.action ~= "none") then
            return false, "Healthcheck setting is not updated correctly"
        end


        local healthcheckFailed = false
        while true do
            local line = ascendOutput:read("l", 1)
            print(line)
            if line and line:match("healthcheck for date:default failed with exit code 1") then
                healthcheckFailed = true
            end
            if line and line:match("restarting date:default") then
                return false, "service restarted and it should have not"
            end

            if healthcheckFailed and os.time() > startTime + 5 then
                break
            end
        end

        return true
    end):result()
    test.assert(result, err)
end
