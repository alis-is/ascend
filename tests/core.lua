local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

test["core - signle module - automatic start"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                sourcePath = "assets/services/simple-date.hjson",
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
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l")
            if line and line:match("date started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        -- check log exists
        local logDir = env:get_log_dir()
        local logFile = path.combine(logDir, "date/default.log")
        while true do
            local logContent = fs.read_file(logFile)
            if logContent and logContent:match("date:") and logContent:match("service start") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not write to log in time"
            end
        end
        return true
    end):run(function()
        return true -- some other test if needed
    end):result()
    test.assert(result, err)
end


if not TEST then
    test.summary()
end
