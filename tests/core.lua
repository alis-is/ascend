local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

DISABLE_CLEANUP = false --- disable to see the tmp directory

test["core - timeout"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-date.hjson",
                definition = {
                    working_dir = "tmp", --- in case of this service it does not make a difference
                    restart = "always",
                    restart_delay = 5,
                    -- log_file = "none" -- inherits stdout/stderr
                }
            }
        },
        assets = {
            ["scripts/date.lua"] = "assets/scripts/date.lua"
        }
    }
    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local start_time = os.time()
        local found = false

        while start_time + 15 > os.time() do -- wait for service started
            local line = ascendOutput:read("l", 2)
            if line:match("timed out") then
                found = true
                break
            end
        end

        if not found then
            return false, "timed out message not found"
        end

        return true
    end, { "--timeout=10s" }):result()
    test.assert(result, err)
end

require "core-single"
require "core-multi"

if not TEST then
    test.summary()
end
