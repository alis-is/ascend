local test = TEST or require "u-test"
local new_test_env = require "common.test-env"
local signal = require "os.signal"

-- single module tests

test["core - single module - automatic start"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-date.hjson",
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

test["core - single module - automatic start (2 services)"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-date.hjson",
            },
            ["one"] = {
                source_path = "assets/services/simple-one-time.hjson",
            },
        },
        assets = {
            ["scripts/date.lua"] = "assets/scripts/date.lua",
            ["scripts/one-time.lua"] = "assets/scripts/one-time.lua",
        }
    }
    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()
        local dateStarted = false
        local oneStarted = false

        while true do -- wait for both services to be started
            local line = ascendOutput:read("l", 2)
            if line and line:match("date:default started") then
                dateStarted = true
            end
            if line and line:match("one:default started") then
                oneStarted = true
            end

            if dateStarted and oneStarted then
                break
            end

            if os.time() > startTime + 10 then
                if not dateStarted then
                    return false, "Date service did not start in time"
                end
                if not oneStarted then
                    return false, "One-time service did not start in time"
                end
            end
        end

        -- check logs exists
        local logDir = env:get_log_dir()
        local dateLogFile = path.combine(logDir, "date/default.log")
        local oneLogFile = path.combine(logDir, "date/default.log")

        local dateLogFound = false
        local oneLogFound = false
        while true do
            local dateLogContent = fs.read_file(dateLogFile)
            local oneLogContent = fs.read_file(oneLogFile)
            if dateLogContent and dateLogContent:match("date:") and dateLogContent:match("service start") then
                dateLogFound = true
            end
            if oneLogContent and oneLogContent:match("date:") and oneLogContent:match("service start") then
                oneLogFound = true
            end

            if dateLogFound and oneLogFound then
                break
            end

            if os.time() > startTime + 10 then
                if not dateLogFound then
                    return false, "Date service did not write to log in time"
                end
                if not oneLogFound then
                    return false, "One service did not write to log in time"
                end
            end
        end
        return true
    end):result()
    test.assert(result, err)
end

test["core - single module - manual start"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-date.hjson",
                definition = {
                    autostart = false,
                }
            }
        },
        assets = {
            ["scripts/date.lua"] = "assets/scripts/date.lua"
        }
    }

    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        while true do
            local line = ascendOutput:read("l", 2)
            if line and line:match("date started") then
                return false, "Service started automatically"
            end
            if os.time() > startTime + 5 then
                break
            end
        end

        local ok, outputOrError = env:asctl({ "start", "date" })
        if not ok then
            return false, outputOrError
        end

        while true do -- wait for service started
            local line = ascendOutput:read("l")
            if line and line:match("date:default started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        return true
    end):result()
    test.assert(result, err)
end

test["core - single module - delayed start"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-date.hjson",
                definition = {
                    start_delay = 2,
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
            if line and line:match("date:default started %(delayed%)") then
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
                source_path = "assets/services/simple-date.hjson",
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

        -- stop the service
        local ok, outputOrError = env:asctl({ "stop", "date" })
        if not ok then
            return false, outputOrError
        end

        while true do -- wait for service stopped
            local line = ascendOutput:read("l", 2)
            if line and line:match("date:default stopped") then
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

test["core - single module - stop signal"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-date.hjson",
                definition = {
                    stop_signal = signal.SIGINT
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

        -- stop the service
        local ok, outputOrError = env:asctl({ "stop", "date" })
        if not ok then
            return false, outputOrError
        end

        while true do -- wait for service stopped
            local line = ascendOutput:read("l", 2)
            if line and line:match("date:default stopped") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not stop in time"
            end
        end

        local ok, outputOrError = env:asctl({ "show", "date" })
        if not ok then
            return false, outputOrError
        end
        local hjson = require "hjson"
        local output = outputOrError
        local show_result = hjson.decode(output)

        return show_result.date.default.stop_signal == 2
    end):result()
    test.assert(result, err)
end

test["core - single module - stop timeout (kill)"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["ignoreSigterm"] = {
                source_path = "assets/services/simple-ignore-sigterm.hjson",
                definition = {
                    restart = "never",
                }
            }
        },
        assets = {
            ["scripts/ignore-sigterm.lua"] = "assets/scripts/ignore-sigterm.lua"
        }
    }
    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l", 2)
            if line and line:match("ignoreSigterm:default started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        -- stop the service
        local ok, outputOrError = env:asctl({ "stop", "ignoreSigterm" })
        if not ok then
            return false, outputOrError
        end

        while true do
            local line = ascendOutput:read("l", 2)
            if line and line:match("ignoreSigterm:default stopped %(killed%)") then
                break
            end
            if os.time() > startTime + 20 then
                return false, "Service did not stop in time"
            end
        end

        return true
    end):result()
    test.assert(result, err)
end

test["core - single module - restart always"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["one"] = {
                source_path = "assets/services/simple-one-time.hjson",
                definition = {
                    restart = "always",
                    restart_max_retries = 1,
                }
            },
        },
        assets = {
            ["scripts/one-time.lua"] = "assets/scripts/one-time.lua",
        }
    }

    local result, err = new_test_env(options):run(function(_, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l", 2)
            if line and line:match("one:default started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        while true do -- wait for service exists
            local line = ascendOutput:read("l")
            if line and line:match("one:default exited with code 0") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not stop in time"
            end
        end

        local stopTime = os.time()
        local retries = 0
        while true do -- wait for service to restart
            local line = ascendOutput:read("l", 2, "s")
            if line and line:match("restarting one:default") then
                retries = retries + 1
            end

            if retries > 1 then
                break
            end

            if os.time() > stopTime + 10 then
                return false, "Service did not restart in time"
            end
        end

        return true
    end):result()
    test.assert(result, err)
end

test["core - single module - restart never"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["one"] = {
                source_path = "assets/services/simple-one-time.hjson",
                definition = {
                    restart = "never",
                }
            },
        },
        assets = {
            ["scripts/one-time.lua"] = "assets/scripts/one-time.lua",
        }
    }

    local result, err = new_test_env(options):run(function(_, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l", 2)
            if line and line:match("one:default started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        while true do -- wait for service exists
            local line = ascendOutput:read("l", 2)
            if line and line:match("one:default exited with code 0") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not stop in time"
            end
        end

        local stopTime = os.time()
        while true do
            local line = ascendOutput:read("l", 2)
            if line and line:match("restarting one:default") then
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

test["core - single module - restart on-exit"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["one"] = {
                source_path = "assets/services/simple-one-time.hjson",
                definition = {
                    restart = "on-exit",
                    restart_max_retries = 2,
                }
            },
        },
        assets = {
            ["scripts/one-time.lua"] = "assets/scripts/one-time.lua",
        }
    }

    local result, err = new_test_env(options):run(function(_, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l", 2)
            if line and line:match("one:default started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        while true do -- wait for service exists
            local line = ascendOutput:read("l", 2)
            if line and line:match("one:default exited with code 0") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not stop in time"
            end
        end

        local stopTime = os.time()
        local retries = 0
        while true do -- wait for service to restart
            local line = ascendOutput:read("l", 2)
            if line and line:match("restarting one:default") then
                retries = retries + 1
            end

            if retries > 2 then
                return false, "Service did not respect restart_max_retries. Restarted more times."
            end

            if os.time() > stopTime + 10 then
                break
            end
        end

        if retries < 2 then
            return false, "Service did not respect restart_max_retries. Restarted less times."
        end

        return true
    end):result()
    test.assert(result, err)
end

test["core - single module - restart on-failure"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["oneFail"] = {
                source_path = "assets/services/simple-one-time-fail.hjson",
                definition = {
                    restart = "on-failure",
                }
            },
        },
        assets = {
            ["scripts/one-time-fail.lua"] = "assets/scripts/one-time-fail.lua",
        }
    }

    local result, err = new_test_env(options):run(function(_, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l", 2)
            if line and line:match("oneFail:default started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        while true do -- wait for service exists
            local line = ascendOutput:read("l", 2)
            if line and line:match("oneFail:default exited with code 1") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not stop in time"
            end
        end

        while true do -- wait for service to restart
            local line = ascendOutput:read("l", 2)
            if line and line:match("restarting oneFail:default") then
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


test["core - single module - restart on-success"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["one"] = {
                source_path = "assets/services/simple-one-time.hjson",
                definition = {
                    restart = "on-success",
                }
            },
        },
        assets = {
            ["scripts/one-time.lua"] = "assets/scripts/one-time.lua",
        }
    }

    local result, err = new_test_env(options):run(function(_, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l", 2)
            if line and line:match("one:default started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        while true do -- wait for service exists
            local line = ascendOutput:read("l", 2)
            if line and line:match("one:default exited with code 0") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not stop in time"
            end
        end

        while true do -- wait for service to restart
            local line = ascendOutput:read("l", 2)
            if line and line:match("restarting one:default") then
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

test["core - single module - restart delay"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["one"] = {
                source_path = "assets/services/simple-one-time.hjson",
                definition = {
                    restart_delay = 3,
                }
            },
        },
        assets = {
            ["scripts/one-time.lua"] = "assets/scripts/one-time.lua",
        }
    }

    local result, err = new_test_env(options):run(function(_, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l", 2)
            if line and line:match("one:default started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        while true do -- wait for service exists
            local line = ascendOutput:read("l", 2)
            if line and line:match("one:default exited with code 0") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not stop in time"
            end
        end

        local stopTime = os.time()
        while true do -- wait for service to restart
            local line = ascendOutput:read("l", 2)
            if line and line:match("restarting one:default") then
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

test["core - single module - restart max retries"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["one"] = {
                source_path = "assets/services/simple-one-time.hjson",
                definition = {
                    restart = "on-exit",
                    restart_max_retries = 6, -- we check with 6 because default is 5
                }
            },
        },
        assets = {
            ["scripts/one-time.lua"] = "assets/scripts/one-time.lua",
        }
    }

    local result, err = new_test_env(options):run(function(_, ascendOutput)
        local startTime = os.time()

        while true do -- wait for service started
            local line = ascendOutput:read("l", 2)
            if line and line:match("one:default started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        while true do -- wait for service exists
            local line = ascendOutput:read("l", 2)
            if line and line:match("one:default exited with code 0") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not stop in time"
            end
        end

        local maxRetries = 0
        while true do -- wait for service to restart
            local line = ascendOutput:read("l", 2)


            if line and line:match("restarting one:default") then
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

test["core - single module - working directory"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["workingDir"] = {
                source_path = "assets/services/simple-working-dir.hjson",
                definition = {
                    working_directory = "workindDirectory",
                }
            }
        },
        assets = {
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
            if line and line:match("workingDir:default started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        -- check log exists
        local logDir = env:get_log_dir()
        local logFile = path.combine(logDir, "workingDir/default.log")
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

if not TEST then
    test.summary()
end
