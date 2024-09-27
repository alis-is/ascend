local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

test["core - multi module - working directory"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["multi"] = {
                source_path = "assets/services/multi-module-working-dir.hjson",
                definition = {
                    working_directory = "workindDirectory",
                }
            }
        },
        assets = {
            ["scripts/date.lua"] = "assets/scripts/date.lua",
            ["scripts/working-dir.lua"] = "assets/scripts/working-dir.lua"
        },
        directories = {
            "workindDirectory"
        }
    }
    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l", 2)
            if line and line:match("multi:workingDir started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        -- check log exists
        local logDir = env:get_log_dir()
        local logFile = path.combine(logDir, "multi/workingDir.log")
        while true do
            local logContent = fs.read_file(logFile)
            if logContent and logContent:match("workindDirectory") then
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
