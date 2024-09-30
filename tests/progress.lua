local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

test["core - single module - automatic start"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-date.hjson",
                definition = {
                    -- working_dir = "tmp", --- in case of this service it does not make a difference
                    -- restart = "always",
                    -- restart_delay = 5,
                    -- log_file = "none" -- inherits stdout/stderr
                    healthcheck = {
                        name = "healthchecks/exit1",
                        action = "restart",
                        delay = 0,
                        retries = 3,
                        interval = 1,
                    }
                }
            }
        },
        assets = {
            ["scripts/date.lua"] = "assets/scripts/date.lua",
        },
        healthchecks = {
            ["exit1"] = "assets/healthchecks/exit1"
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

        while true do
            print(ascendOutput:read("l", 2))
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
    end):result()
    test.assert(result, err)
end


-- {
--     executable: bash
--     args: [
--         ./date.sh
--     ]
--     working_directory: ../tests/assets/scripts
--     start_delay: 30
--     restart: always
--     restart_delay: 5
-- 	restart_max_retries: 1
--     // healthcheck: {
--     //     name: exit1
--     //     action: restart
--     //     delay: 0
-- 	// 	retries: 3
-- 	// 	interval: 1
--     // }
-- }
