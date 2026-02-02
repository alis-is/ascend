#!/usr/bin/env eli

require "common.globals"
require "common.log" ("asctl")
local format = require "asctl.format"
local log = require "asctl.log"

local args = require "common.args"

if args.command == "version" or args.options["version"] then
	print(string.interpolate("asctl ${version}", { version = require "version-info".VERSION }))
	os.exit(0)
end

local client = require "asctl.client"

GLOBAL_LOGGER.options.level = args.options["log-level"] or "info"

local commands = {
	start = function(parameters, _)
		local response, err = client.execute("start", parameters)
		if not response then
			log_error(err --[[ @as string ]])
			os.exit(1)
		end
		local stop_jobs = response.data
		for name, result in pairs(stop_jobs) do
			if not result.ok then
				log_error(string.interpolate("failed to start ${name}: ${error}", { name = name, error = result.error }))
			else
				log_info(string.interpolate("${name} started", { name = name }))
			end
		end
	end,
	stop = function(parameters, _)
		local response, err = client.execute("stop", parameters)
		if not response then
			log_error(err --[[ @as string ]])
			os.exit(1)
		end
		local stop_jobs = response.data
		for name, result in pairs(stop_jobs) do
			if not result.ok then
				log_error(string.interpolate("failed to stop ${name}: ${error}", { name = name, error = result.error }))
			else
				log_info(string.interpolate("${name} stopped", { name = name }))
			end
		end
	end,
	restart = function(parameters, _)
		local response, err = client.execute("restart", parameters)
		if not response then
			log_error(err --[[ @as string ]])
			os.exit(1)
		end
		local stop_jobs = response.data
		for name, result in pairs(stop_jobs) do
			if not result.ok then
				log_error(string.interpolate("failed to restart ${name}: ${error}", { name = name, error = result.error }))
			else
				log_info(string.interpolate("${name} restarted", { name = name }))
			end
		end
	end,
	reload = function(parameters, _)
		local response, err = client.execute("reload", parameters)
		if not response then
			log_error(string.interpolate("failed to reload: ${error}", { error = err }))
		else
			log_info("reloaded")
		end
	end,
	["ascend-health"] = function(parameters, _)
		local response, err = client.execute("ascend-health", parameters)
		if not response then
			log_error(err --[[ @as string ]])
			os.exit(1)
		end
		if response.data ~= "healthy" then
			log_error("not healthy")
			os.exit(1)
		else
			log_info("healthy")
		end
	end,
	list = function(parameters, options)
		parameters.options = options

		local response, err = client.execute("list", parameters)
		if not response then
			log_error(err --[[ @as string ]])
			os.exit(1)
		end
		print(format.list(response.data))
	end,
	status = function(parameters, _)
		local response, err = client.execute("status", parameters)
		if not response then
			log_error(err --[[ @as string ]])
			os.exit(1)
		end
		print(format.status(response.data))
	end,
	show = function(parameters, _)
		local response, err = client.execute("show", parameters)
		if not response then
			log_error(err --[[ @as string ]])
			os.exit(1)
		end
		print(format.show(response.data))
	end,
	cat = function(parameters, _)
		local response, err = client.execute("cat", parameters)
		if not response then
			log_error(err --[[ @as string ]])
			os.exit(1)
		end

		local output = response.data
		local printed = false
		local function emit(service_name)
			local entry = output[service_name]
			if not entry then
				return
			end
			if printed then
				io.write("\n")
			end
			if type(entry.source) == "string" then
				print("# " .. entry.source)
			end
			if type(entry.content) == "string" then
				io.write(entry.content)
				if entry.content:sub(-1) ~= "\n" then
					io.write("\n")
				end
			end
			printed = true
		end

		if type(parameters) == "table" and #parameters > 0 then
			for _, name in ipairs(parameters) do
				local service_name = name:match("^(.+):") or name
				emit(service_name)
			end
		else
			for service_name, _ in pairs(output) do
				emit(service_name)
			end
		end
	end,
	logs = function(parameters, options)
		local response, err = client.execute("logs", parameters)
		if not response then
			log_error(err --[[ @as string ]])
			os.exit(1)
		end
		local services = response.data
		local log_sources = {}
		for service, modules in pairs(services) do
			for module, log_file_path in pairs(modules) do
				log_sources[service .. ":" .. module] = log_file_path
			end
		end
		local timeout_str = options.timeout
		local timeout = tonumber(timeout_str)
		if (timeout_str and (timeout == nil or timeout < 0)) then
			log_error(string.interpolate("invalid timeout: ${timeout}", { timeout = timeout_str }))
			os.exit(1)
		end
		if options.follow or options.f or options.timeout then
			log.stream(log_sources, timeout)
		else
			log.stream(log_sources, 1)
		end
	end
}

if commands[args.command] then
	commands[args.command](args.parameters, args.options)
	return
end

log_error(string.interpolate("unknown command: ${command}", { command = args.command }))
os.exit(1)
