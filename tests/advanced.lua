local test = TEST or require "u-test"
local new_test_env = require "common.test-env"


test["advanced - init - lua"] = function()
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
            ASCEND_INIT = "${ENV_DIR}/assets/scripts/ascend-init.lua"
        },
    }
    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        while true do
            local line = ascendOutput:read("l", 2)
            if line and line:match("script initialized") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did run the init script in time"
            end
        end

        return true
    end):result()
    test.assert(result, err)
end

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
            ["scripts/ascend-init.sh"] = "assets/scripts/ascend-init.sh"
        },
        environment_variables = {
            ASCEND_INIT = "${ENV_DIR}/assets/scripts/ascend-init.sh"
        },
    }
    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        while true do
            local line = ascendOutput:read("l", 2)
            if line and line:match("script initialized") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did run the init script in time"
            end
        end

        return true
    end):result()
    test.assert(result, err)
end
