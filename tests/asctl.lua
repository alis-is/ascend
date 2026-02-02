local test = TEST or require "u-test"
local new_test_env = require "common.test-env"

DISABLE_CLEANUP = false --- disable to see the tmp directory

test["asctl - list"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-date.hjson",
            },
            ["date2"] = {
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
            if line == nil then os.exit(1) end
            if line and line:match("date:default started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        local ok, outputOrError = env:asctl({ "list" })
        if not ok then
            return false, outputOrError
        end

        local output = outputOrError
        return output:match("date") and output:match("date2")
    end):result()
    test.assert(result, err)
end

test["asctl - list --extended"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["date"] = {
                source_path = "assets/services/simple-date.hjson",
            },
            ["date2"] = {
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

        local ok, outputOrError = env:asctl({ "list", "--extended" })
        if not ok then
            return false, outputOrError
        end

        local output = outputOrError
        return output:match("date") and output:match("date2") and output:match("pid") and output:match("state")
    end):result()
    test.assert(result, err)
end

test["asctl - stop"] = function()
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

test["asctl - stop only one module"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["multi"] = {
                source_path = "assets/services/multi-module.hjson",
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
            local line = ascendOutput:read("l", 2)
            if line and line:match("multi:date started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        -- stop the service
        local ok, outputOrError = env:asctl({ "stop", "multi:one" })
        if not ok then
            return false, outputOrError
        end

        local stopTime = os.time()
        local oneStopped = false
        while true do -- wait for service stopped
            local line = ascendOutput:read("l", 1)
            if line and line:match("multi:date stopped") then
                oneStopped = true
            end

            if line and line:match("multi:date stopped") then
                return false, 'Wrong module stopped'
            end

            if os.time() > stopTime + 5 then
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

test["asctl - start"] = function()
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
            if line and line:match("date:default started") then
                return false, "Service started automatically"
            end
            if os.time() > startTime + 5 then
                break
            end
        end

        -- start the service
        local ok, outputOrError = env:asctl({ "start", "date" })
        if not ok then
            return false, outputOrError
        end

        while true do -- wait for service started
            local line = ascendOutput:read("l", 2)
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

test["asctl - restart"] = function()
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

        -- restart the service
        local ok, outputOrError = env:asctl({ "restart", "date" })
        if not ok then
            return false, outputOrError
        end

        local steps = 0 -- at 2 steps we consider test completed (stop + start)
        while true do
            local line = ascendOutput:read("l", 2)
            if line and (line:match("date:default stopped") or line:match("date:default started")) then
                steps = steps + 1
            end
            if steps == 2 then
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

test["asctl - reload"] = function()
    ---@type AscendTestEnvOptions
    local options = {
        services = {
            ["one"] = {
                source_path = "assets/services/simple-one-time.hjson",
                definition = {
                    restart = "never",
                }
            }
        },
        assets = {
            ["scripts/one-time.lua"] = "assets/scripts/one-time.lua"
        }
    }

    local result, err = new_test_env(options):run(function(env, ascendOutput)
        local startTime = os.time()

        ---@type AscendTestEnvOptions
        local newOptions = {
            services = {
                ["one"] = {
                    source_path = "assets/services/simple-one-time.hjson",
                    definition = {
                        restart = "always",
                    }
                }
            },
            assets = {
                ["scripts/one-time.lua"] = "assets/scripts/one-time.lua"
            }
        }

        while true do -- wait for service started
            local line = ascendOutput:read("l", 2)
            if line and line:match("one:default started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        -- update the environment with new options
        local ok, err = env:update_env(newOptions)
        if not ok then
            return false, err
        end

        -- reload the service
        local ok, outputOrError = env:asctl({ "reload" })

        if not ok then
            return false, outputOrError
        end

        while true do
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

test["asctl - ascend-health"] = function()
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

        local ok, outputOrError = env:asctl({ "ascend-health" })
        if not ok then
            return false, outputOrError
        end

        local output = outputOrError
        return output:match("healthy")
    end):result()
    test.assert(result, err)
end

test["asctl - status"] = function()
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

        local ok, outputOrError = env:asctl({ "status", "date" })
        if not ok then
            return false, outputOrError
        end

        local output = outputOrError
        return output:match("date") and output:match("status") and output:match('"ok":true')
    end):result()
    test.assert(result, err)
end

test["asctl - show"] = function()
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

        return type(show_result.date) == "table" and
            type(show_result.date.default.executable) == "string" and show_result.date.default.executable:match("eli") and
            type(show_result.date.default.args) == "table" and #show_result.date.default.args == 1 and
            show_result.date.default.args[1]:match("scripts/date.lua") and
            type(show_result.date.default.autostart) == "boolean" and show_result.date.default.autostart == true and
            type(show_result.date.default.restart) == "string" and show_result.date.default.restart == "on-exit"
    end):result()
    test.assert(result, err)
end

test["asctl - cat"] = function()
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

        local ok, outputOrError = env:asctl({ "cat", "date" })
        if not ok then
            return false, outputOrError
        end

        local output = outputOrError
        return output:match("# .+date%.hjson") and
            output:match("executable") and
            output:match("date%.lua")
    end):result()
    test.assert(result, err)
end

test["asctl - logs"] = function()
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

        local ok, outputOrError = env:asctl({ "logs", "date", "--timeout=7" })
        if not ok then
            return false, outputOrError
        end

        local output = outputOrError
        local count = 0
        for line in output:gmatch("[^\n]+") do
            if line:match("date:default | date:") then
                count = count + 1
            end
        end

        if count < 2 then
            return false, "Expected log message not found 2 times"
        end
        return true
    end):result()
    test.assert(result, err)
end

test["asctl - logs -f"] = function()
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
            local line = ascendOutput:read("l")
            if line and line:match("date:default started") then
                break
            end
            if os.time() > startTime + 10 then
                return false, "Service did not start in time"
            end
        end

        local ok, error = env:asctl({ "logs", "date", "-f" }, 10)
        local timed_out = not ok and error:match("timeout")
        if not timed_out then
            return false, "should time out"
        end

        return true
    end):result()
    test.assert(result, err)
end

if not TEST then
    test.summary()
end
