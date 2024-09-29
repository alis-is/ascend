local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

local function read_file(file_path)
    local file = io.open(file_path, "r")
    if file then
        local content = file:read("*all")
        file:close()
        return content
    else
        return nil
    end
end

test["logs - max files"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-one-kb.hjson",
                definition = {
                    -- log_file = "none" -- inherits stdout/stderr
                    log_max_size = 1024,
                    log_rotate = true,
                    log_max_files = 2
                }
            }
        },
        assets = {
            ["scripts/one-kb.lua"] = "assets/scripts/one-kb.lua"
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

        local logDir = env:get_log_dir()
        local logFile = path.combine(logDir, "date/default.log")
        local exceededLogFile = path.combine(logDir, "date/default.log.2")

        while true do
            local exceededLogFileContent = read_file(exceededLogFile)
            os.sleep(1)

            if exceededLogFileContent then
                return false, "Exceeded max log files"
            end


            if os.time() > startTime + 5 then
                break
            end
        end

        return true
    end):result()
    test.assert(result, err)
end
