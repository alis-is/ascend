local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

test["asctl - reload"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["one"] = {
                source_path = "assets/services/simple-one-time.hjson",
                definition = {
                    restart = "never",
                }
            }
        },
        assets = {
            ["scripts/one-time.lua"] = "assets/scripts/one-time.lua"
        }
    }

    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        ---@type AscendTestEnvOptions
        local newOptions = {
            services = {
                ["one"] = {
                    source_path = "assets/services/simple-one-time.hjson",
                    definition = {
                        restart = "always",
                    }
                }
            },
            assets = {
                ["scripts/one-time.lua"] = "assets/scripts/one-time.lua"
            }
        }

        while true do -- wait for service started
            local line = ascendOutput:read("l")
            if line and line:match("one started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        -- update the environment with new options
        local ok, err = env:update_env(newOptions)
        if not ok then
            return false, err
        end

        -- reload the service
        local ok, outputOrError = env:asctl({ "reload", "one" })
        if not ok then
            return false, outputOrError
        end

        while true do
            local line = ascendOutput:read("l", 2)
            if line and line:match("restarting one:default") then
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
