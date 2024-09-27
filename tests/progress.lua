local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

test["core - single module - working directory"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["workingDir"] = {
                source_path = "assets/services/simple-working-dir.hjson",
                definition = {
                    working_directory = "environments",

                }
            }
        },
        assets = {
            ["scripts/working-dir.lua"] = "assets/scripts/working-dir.lua"
        }
    }
    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l", 2)
            print(line)
            if line and line:match("workingDir:default started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end


        print(options.services.workingDir.definition.working_directory) --returns nil if i do not define it in definitition

        -- check log exists
        local logDir = env:get_log_dir()
        local logFile = path.combine(logDir, "workingDir/default.log")
        while true do
            local logContent = fs.read_file(logFile)
            -- print(logContent)
            -- if logContent and logContent:match("date:") and logContent:match("service start") then
            --     break
            -- end
            -- if os.time() > startTime + 10 then
            --     return false, "Service did not write to log in time"
            -- end
        end
        return true
    end):result()
    test.assert(result, err)
end
