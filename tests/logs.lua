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

test["logs - rotate"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-one-kb.hjson",
                definition = {
                    log_max_size = 1024,
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
        local rotatedLogFile = path.combine(logDir, "date/default.log.1")

        local previousLogContent
        local previousRotatedLogContent

        local logFileIsRotated = false
        local oldLogFileIsRotated = false

        while true do
            local logContent = read_file(logFile)
            local rotatedLogContent = read_file(rotatedLogFile)
            os.sleep(1)

            if previousLogContent and logContent ~= previousLogContent then
                logFileIsRotated = true
            end
            if previousRotatedLogContent and rotatedLogContent ~= previousRotatedLogContent then
                oldLogFileIsRotated = true
            end
            if logFileIsRotated and oldLogFileIsRotated then
                break
            end

            previousLogContent = logContent
            previousRotatedLogContent = rotatedLogContent
            if os.time() > startTime + 10 then
                return false, "Service did not write to log in time"
            end
        end

        return true
    end):result()
    test.assert(result, err)
end

test["logs - simple file"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-date.hjson",
                definition = {
                    log_file = "date/date.log"
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

        -- check log exists
        local logDir = env:get_log_dir()
        local logFile = path.combine(logDir, "date/date.log")
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
        local nextLogFile = path.combine(logDir, "date/default.log.2")

        while true do
            local logFileSize = get_file_size(logFile)
            local nextLogFileExists = read_file(nextLogFile) ~= nil
            os.sleep(1)

            if logFileSize and logFileSize > 1024 and nextLogFileExists then
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

test["logs - max files"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-one-kb.hjson",
                definition = {
                    log_max_size = 1024,
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
