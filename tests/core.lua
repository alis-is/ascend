local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

test["core - single module - automatic start"] = function()
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

test["core - single module - stop"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                sourcePath = "assets/services/simple-date.hjson",
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

        -- stop the service
        local ok, outputOrError = env:asctl({ "stop", "date" })
        if not ok then
            return false, outputOrError
        end

        while true do -- wait for service stopped
            local line = ascendOutput:read("l")
            if line and line:match("date stopped") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not stop in time"
            end
        end

        return true
    end):result()
    test.assert(result, err)
end

-- test["core - single module - restart always"] = function()
--     ---@type AscendTestEnvOptions
--     local options = {
--         services = {
--             ["one"] = {
--                 sourcePath = "assets/services/simple-one-time.hjson",
--                 definition = {
--                     restart = "always",
--                     restart_delay = 3,
--                 }
--             },
--         },
--         assets = {
--             ["scripts/one-time.lua"] = "assets/scripts/one-time.lua",
--         }
--     }

--     local result, err = new_test_env(options):run(function(env, ascendOutput)
--         local startTime = os.time()
--         while true do -- wait for service started
--             print(ascendOutput:read("l"))
--         end


--         while true do -- wait for service started
--             local line = ascendOutput:read("l")
--             print(line)
--             if line and line:match("one started") then
--                 break
--             end
--             if os.time() > startTime + 10 then
--                 return false, "Service did not start in time"
--             end
--         end

--         while true do -- wait for service stopped
--             local line = ascendOutput:read("l")
--             print(line)
--             if line and line:match("one stopped") then
--                 break
--             end
--             if os.time() > startTime + 10 then
--                 return false, "Service did not stop in time"
--             end
--         end

--         while true do -- wait for service to restart
--             local line = ascendOutput:read("l")
--             print(line)
--             if line and line:match("one started") then
--                 break
--             end
--             if os.time() > startTime + 10 then
--                 return false, "Service did not restart in time"
--             end
--         end

--         return true
--     end):result()
--     test.assert(result, err)
-- end

if not TEST then
    test.summary()
end
