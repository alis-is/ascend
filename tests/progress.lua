local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

test["asctl - reload"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["one"] = {
                sourcePath = "assets/services/simple-one-time.hjson",
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
        options = {
            services = {
                ["one"] = {
                    sourcePath = "assets/services/simple-one-time.hjson",
                    definition = {
                        restart = "never",
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

        local ok, err = env:update_env(options)
        if not ok then
            return false, "Error on update environment"
        end

        -- reload the service
        local ok, outputOrError = env:asctl({ "reload", "one" })

        print(outputOrError)
        while true do
            print(ascendOutput:read("l", 3))
        end
        if not ok then
            return false, outputOrError
        end

        return true
    end):result()
    test.assert(result, err)
end
