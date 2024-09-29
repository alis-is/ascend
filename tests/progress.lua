local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

local function get_file_size(file_path)
    local file = io.open(file_path, "r")
    if file then
        local size = file:seek("end")
        file:close()
        return size
    else
        return nil
    end
end

test["logs - max size"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-one-kb.hjson",
                definition = {
                    log_max_size = 1024,
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
        local logFile = path.combine(logDir, "date/default.log.1")

        while true do
            local logFileSize = get_file_size(logFile)
            os.sleep(1)
            if logFileSize then
                print(logFileSize)
            end

            if logFileSize and logFileSize < 1024 then
                break
            end

            if os.time() > startTime + 10 then
                return false, "Log max size failed, either no log was written or size > 1024"
            end
        end

        return true
    end):result()
    test.assert(result, err)
end
