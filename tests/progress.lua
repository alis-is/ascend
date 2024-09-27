local test = TEST or require "u-test"
local new_test_env = require "common.test-env"
local signal = require "os.signal"

test["core - single module - stop signal"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-date.hjson",
                definition = {
                    stop_signal = signal.SIGINT
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

        -- stop the service
        local ok, outputOrError = env:asctl({ "stop", "date" })
        if not ok then
            return false, outputOrError
        end

        local ok, outputOrError = env:asctl({ "show", "date" })
        if not ok then
            return false, outputOrError
        end
        local hjson = require "hjson"
        local output = outputOrError
        local show_result = hjson.decode(output)


        while true do -- wait for service stopped
            local line = ascendOutput:read("l", 2)
            if line and line:match("date:default stopped") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not stop in time"
            end
        end

        return show_result.date.default.stop_signal == 2
    end):result()
    test.assert(result, err)
end

test["core - multi module - stop signal"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["multi"] = {
                source_path = "assets/services/multi-module.hjson",
                definition = {
                    stop_signal = signal.SIGINT
                }
            },
        },
        assets = {
            ["scripts/date.lua"] = "assets/scripts/date.lua",
            ["scripts/one-time.lua"] = "assets/scripts/one-time.lua",
        }
    }

    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l", 2)
            if line and line:match("multi:date started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        -- stop the service
        local ok, outputOrError = env:asctl({ "stop", "multi:date" })
        if not ok then
            return false, outputOrError
        end

        while true do -- wait for service stopped
            local line = ascendOutput:read("l", 2)
            if line and line:match("multi:date stopped") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not stop in time"
            end
        end

        local ok, outputOrError = env:asctl({ "show", "multi:date" })
        if not ok then
            return false, outputOrError
        end
        local hjson = require "hjson"
        local output = outputOrError
        local show_result = hjson.decode(output)

        return show_result.multi.date.stop_signal == 2
    end):result()
    test.assert(result, err)
end
