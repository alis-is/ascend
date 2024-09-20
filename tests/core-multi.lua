local test = TEST or require "u-test"
local new_test_env = require "common.test-env"


-- multiple modules tests

test["core - multi module - automatic start"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["multi"] = {
                sourcePath = "assets/services/multi-module.hjson",
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
            local line = ascendOutput:read("l")
            if line and line:match("multi started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        -- check log exists
        local logDir = env:get_log_dir()
        local logFile = path.combine(logDir, "multi/date.log")
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

test["core - multi module - stop"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["multi"] = {
                sourcePath = "assets/services/multi-module.hjson",
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
            local line = ascendOutput:read("l")
            if line and line:match("multi started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        -- stop the service
        local ok, outputOrError = env:asctl({ "stop", "multi" })
        if not ok then
            return false, outputOrError
        end

        while true do -- wait for service stopped
            local line = ascendOutput:read("l")
            if line and line:match("multi stopped") then
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

test["core - multi module - restart on-exit"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["multi"] = {
                sourcePath = "assets/services/multi-module-ending.hjson",
                definition = {
                    restart = "on-exit",
                }
            },
        },
        assets = {
            ["scripts/one-time.lua"] = "assets/scripts/one-time.lua",
            ["scripts/one-time2.lua"] = "assets/scripts/one-time2.lua",
        }
    }

    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l")
            if line and line:match("multi started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        while true do -- wait for service exists
            local line = ascendOutput:read("l")
            if line and line:match("multi:one exited with code 0") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not stop in time"
            end
        end

        while true do -- wait for service to restart
            local line = ascendOutput:read("l")
            if line and line:match("restarting multi") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not restart in time"
            end
        end

        return true
    end):result()
    test.assert(result, err)
end

test["core - multi module - restart never"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["multi"] = {
                sourcePath = "assets/services/multi-module-ending.hjson",
                definition = {
                    restart = "never",
                }
            },
        },
        assets = {
            ["scripts/one-time.lua"] = "assets/scripts/one-time.lua",
            ["scripts/one-time2.lua"] = "assets/scripts/one-time2.lua",
        }
    }

    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l", 2, "s")
            if line and line:match("multi started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        while true do -- wait for service exists
            local line = ascendOutput:read("l", 2, "s")
            if line and line:match("multi:one exited with code 0") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not stop in time"
            end
        end

        local stopTime = os.time()
        while true do
            local line = ascendOutput:read("l", 2, "s")
            if line and line:match("restarting multi") then
                return false, "Service did restart"
            end

            if os.time() > stopTime + 5 then
                break
            end
        end

        return true
    end):result()
    test.assert(result, err)
end

test["core - multi module - restart on-failure"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["multiFail"] = {
                sourcePath = "assets/services/multi-module-ending-fail.hjson",
                definition = {
                    restart = "on-failure",
                }
            },
        },
        assets = {
            ["scripts/one-time.lua"] = "assets/scripts/one-time.lua",
            ["scripts/one-time-fail.lua"] = "assets/scripts/one-time-fail.lua",
        }
    }

    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l")
            if line and line:match("multiFail started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        while true do -- wait for service exists
            local line = ascendOutput:read("l")
            if line and line:match("multiFail:oneFail exited with code 1") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not stop in time"
            end
        end

        while true do -- wait for service to restart
            local line = ascendOutput:read("l")
            if line and line:match("restarting multiFail") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not restart in time"
            end
        end

        return true
    end):result()
    test.assert(result, err)
end

test["core - multi module - restart on-success"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["multi"] = {
                sourcePath = "assets/services/multi-module-ending.hjson",
                definition = {
                    restart = "on-success",
                }
            },
        },
        assets = {
            ["scripts/one-time.lua"] = "assets/scripts/one-time.lua",
            ["scripts/one-time2.lua"] = "assets/scripts/one-time2.lua",
        }
    }

    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l")
            if line and line:match("multi started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        while true do -- wait for service exists
            local line = ascendOutput:read("l")
            if line and line:match("multi:one exited with code 0") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not stop in time"
            end
        end

        while true do -- wait for service to restart
            local line = ascendOutput:read("l")
            if line and line:match("restarting multi") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not restart in time"
            end
        end

        return true
    end):result()
    test.assert(result, err)
end

test["core - multi module - restart delay"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["multi"] = {
                sourcePath = "assets/services/multi-module-ending.hjson",
                definition = {
                    restart_delay = 3,
                }
            },
        },
        assets = {
            ["scripts/one-time.lua"] = "assets/scripts/one-time.lua",
            ["scripts/one-time2.lua"] = "assets/scripts/one-time2.lua",
        }
    }

    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l")
            if line and line:match("multi started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        while true do -- wait for service exists
            local line = ascendOutput:read("l")
            if line and line:match("multi:one exited with code 0") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not stop in time"
            end
        end

        local stopTime = os.time()
        while true do -- wait for service to restart
            local line = ascendOutput:read("l")
            if line and line:match("restarting multi") then
                break
            end
        end
        if os.time() < stopTime + 3 then
            return false, "Service did not respected the delay of 3 secs"
        end

        return true
    end):result()
    test.assert(result, err)
end

test["core - multi module - restart max retries"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["multi"] = {
                sourcePath = "assets/services/multi-module-ending.hjson",
                definition = {
                    restart = "on-exit",
                    restart_max_retries = 6, -- we check with 6 because default is 5
                }
            },
        },
        assets = {
            ["scripts/one-time.lua"] = "assets/scripts/one-time.lua",
            ["scripts/one-time2.lua"] = "assets/scripts/one-time2.lua",
        }
    }

    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()


        while true do -- wait for service started
            local line = ascendOutput:read("l")
            if line and line:match("multi started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        while true do -- wait for service exists
            local line = ascendOutput:read("l")
            if line and line:match("multi:one exited with code 0") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not stop in time"
            end
        end

        local maxRetries = 0
        while true do -- wait for service to restart
            local line = ascendOutput:read("l")


            if line and line:match("restarting multi") then
                maxRetries = maxRetries + 1
            end
            if maxRetries == 6 then
                break
            end

            if os.time() > startTime + 20 then
                return false, "Service did not restart in time"
            end
        end

        return true
    end):result()
    test.assert(result, err)
end

if not TEST then
    test.summary()
end
