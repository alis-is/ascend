local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

test["ascend"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = "assets/services/simple-date.hjson",
        },
        vars = {
            ["date"] = {
                ["working_dir"] = "tmp",
            },
        },
    }
    local result, err = new_test_env(options):run(function()
        return true
    end):run(function()
        return true
    end):result()
    test.assert(result, err)
end


if not TEST then
    test.summary()
end
