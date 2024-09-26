local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

test["core - multi module - default values"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["multi"] = {
                source_path = "assets/services/multi-module.hjson",
            },
        },
        assets = {
            ["scripts/date.lua"] = "assets/scripts/date.lua",
            ["scripts/one-time.lua"] = "assets/scripts/one-time.lua",
        }
    }

    local expected_defaults = {
        autostart = true,
        restart = "on-exit",
        depends = {},
        log_max_size = 10485760,
        executable = "eli",
        log_max_files = 5,
        log_rotate = true,
        restart_max_retries = 5,
        stop_signal = 15,
        args = { "assets/scripts/date.lua" },
        environment = {},
        log_file = "multi/date.log",
        restart_delay = 1,
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

        local ok, outputOrError = env:asctl({ "show", "multi:date" })
        if not ok then
            return false, outputOrError
        end
        local hjson = require "hjson"
        local output = outputOrError
        local show_result = hjson.decode(output)
        if type(show_result) ~= "table" then
            return false, "failed to decode show result"
        end

        local actual_defaults = table.filter(show_result.multi.date, function(_, key)
            return expected_defaults[key] ~= nil
        end)

        return util.equals(actual_defaults, expected_defaults, true);
    end):result()
    test.assert(result, err)
end

test["core - single module - default values"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-date.hjson",
            },
        },
        assets = {
            ["scripts/date.lua"] = "assets/scripts/date.lua"
        }
    }

    local expected_defaults = {
        autostart = true,
        restart = "on-exit",
        depends = {},
        log_max_size = 10485760,
        executable = "eli",
        log_max_files = 5,
        log_rotate = true,
        restart_max_retries = 5,
        stop_signal = 15,
        args = { "assets/scripts/date.lua" },
        environment = {},
        log_file = "date/default.log",
        restart_delay = 1,
    }

    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service to start
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
        local hjson = require "hjson"
        local output = outputOrError
        local show_result = hjson.decode(output)
        if type(show_result) ~= "table" then
            return false, "failed to decode show result"
        end

        local actual_defaults = table.filter(show_result.date.default, function(_, key)
            return expected_defaults[key] ~= nil
        end)

        return util.equals(actual_defaults, expected_defaults, true);
    end):result()

    test.assert(result, err)
end
