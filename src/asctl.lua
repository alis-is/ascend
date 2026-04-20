#!/usr/bin/env eli

require "common.globals"
require "common.log" ("asctl")
local format = require "asctl.format"
local log = require "asctl.log"
local input = require "common.input"

local args = require "common.args"

local function print_formatted(renderer, data)
	local output = renderer(data)
	if type(output) == "string" and #output > 0 then
		print(output)
	end
end

---@param err string
local function exit_jsonrpc_error(err)
	log_error(err)
	os.exit(EXIT_JSONRPC_ERROR)
end

---@param err string
local function exit_command_error(err)
	log_error(err)
	os.exit(EXIT_COMMAND_ERROR)
end

---@param response any
---@param command string
---@return table
local function expect_table_response(response, command)
	if type(response) ~= "table" then
		exit_jsonrpc_error(string.interpolate("invalid response type for ${command}", { command = command }))
	end
	return response
end

---@param results table<string, { ok: boolean, error: string? }>
---@param action string
local function report_command_results(results, action)
	local has_failures = false
	for name, result in pairs(results) do
		if not result.ok then
			has_failures = true
			log_error(string.interpolate("failed to ${action} ${name}: ${error}", {
				action = action,
				name = name,
				error = result.error,
			}))
		else
			log_info(string.interpolate("${name} ${action}ed", { name = name, action = action }))
		end
	end

	if has_failures then
		os.exit(EXIT_COMMAND_ERROR)
	end
end

if args.options.timeout ~= nil then
	local timeout = input.parse_time_value(args.options.timeout)
	if not timeout or timeout < 0 then
		exit_command_error(string.interpolate("invalid timeout: ${timeout}", {
			timeout = tostring(args.options.timeout),
		}))
	end
	args.options.timeout = timeout
end

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
			exit_jsonrpc_error(err --[[ @as string ]])
		end
		response = expect_table_response(response, "start")
		if response.data == nil then
			exit_jsonrpc_error("invalid response payload for start")
		end
		report_command_results(response.data, "start")
	end,
	stop = function(parameters, _)
		local response, err = client.execute("stop", parameters)
		if not response then
			exit_jsonrpc_error(err --[[ @as string ]])
		end
		response = expect_table_response(response, "stop")
		if response.data == nil then
			exit_jsonrpc_error("invalid response payload for stop")
		end
		report_command_results(response.data, "stop")
	end,
	restart = function(parameters, _)
		local response, err = client.execute("restart", parameters)
		if not response then
			exit_jsonrpc_error(err --[[ @as string ]])
		end
		response = expect_table_response(response, "restart")
		if response.data == nil then
			exit_jsonrpc_error("invalid response payload for restart")
		end
		report_command_results(response.data, "restart")
	end,
	reload = function(parameters, _)
		local response, err = client.execute("reload", parameters)
		if not response then
			exit_jsonrpc_error(string.interpolate("failed to reload: ${error}", { error = err }))
		end
		log_info("reloaded")
	end,
	["ascend-health"] = function(parameters, _)
		local response, err = client.execute("ascend-health", parameters)
		if not response then
			exit_jsonrpc_error(err --[[ @as string ]])
		end
		response = expect_table_response(response, "ascend-health")
		if response.data == nil then
			exit_jsonrpc_error("invalid response payload for ascend-health")
		end
		if response.data ~= "healthy" then
			exit_command_error("not healthy")
		else
			log_info("healthy")
		end
	end,
	list = function(parameters, options)
		parameters.options = options

		local response, err = client.execute("list", parameters)
		if not response then
			exit_jsonrpc_error(err --[[ @as string ]])
		end
		response = expect_table_response(response, "list")
		if response.data == nil then
			exit_jsonrpc_error("invalid response payload for list")
		end
		print_formatted(format.list, response.data)
		if response.success == false then
			os.exit(EXIT_COMMAND_ERROR)
		end
	end,
	status = function(parameters, _)
		local response, err = client.execute("status", parameters)
		if not response then
			exit_jsonrpc_error(err --[[ @as string ]])
		end
		response = expect_table_response(response, "status")
		if response.data == nil then
			exit_jsonrpc_error("invalid response payload for status")
		end
		print_formatted(format.status, response.data)
		if response.success == false then
			os.exit(EXIT_COMMAND_ERROR)
		end
	end,
	show = function(parameters, _)
		local response, err = client.execute("show", parameters)
		if not response then
			exit_jsonrpc_error(err --[[ @as string ]])
		end
		response = expect_table_response(response, "show")
		if response.data == nil then
			exit_jsonrpc_error("invalid response payload for show")
		end
		print_formatted(format.show, response.data)
		if response.success == false then
			os.exit(EXIT_COMMAND_ERROR)
		end
	end,
	cat = function(parameters, _)
		local response, err = client.execute("cat", parameters)
		if not response then
			exit_jsonrpc_error(err --[[ @as string ]])
		end
		response = expect_table_response(response, "cat")
		if response.data == nil then
			exit_jsonrpc_error("invalid response payload for cat")
		end

		local output = response.data

		local service_names = {}
		local seen_services = {}
		if type(parameters) == "table" and #parameters > 0 then
			for _, name in ipairs(parameters) do
				local service_name = name:match("^([^:]+):") or name
				if output[service_name] and not seen_services[service_name] then
					table.insert(service_names, service_name)
					seen_services[service_name] = true
				end
			end
		else
			service_names = table.keys(output)
			table.sort(service_names)
		end

		local show_sources = #service_names > 1
		for index, service_name in ipairs(service_names) do
			local entry = output[service_name]
			if type(entry) == "table" and type(entry.content) == "string" then
				if index > 1 then
					io.write("\n")
				end
				if show_sources and type(entry.source) == "string" then
					print("# " .. entry.source)
				end
				io.write(entry.content)
				if entry.content:sub(-1) ~= "\n" then
					io.write("\n")
				end
			end
		end

		if response.success == false then
			os.exit(EXIT_COMMAND_ERROR)
		end
	end,
	logs = function(parameters, options)
		local response, err = client.execute("logs", parameters)
		if not response then
			exit_jsonrpc_error(err --[[ @as string ]])
		end
		response = expect_table_response(response, "logs")
		if response.data == nil then
			exit_jsonrpc_error("invalid response payload for logs")
		end
		local services = response.data
		local log_sources = {}
		for service, modules in pairs(services) do
			for module, log_file_path in pairs(modules) do
				log_sources[service .. ":" .. module] = log_file_path
			end
		end
		if options.follow or options.f then
			log.stream(log_sources, options.timeout)
		elseif options.timeout ~= nil then
			log.stream(log_sources, options.timeout)
		else
			log.stream(log_sources, 1)
		end
		if response.success == false then
			os.exit(EXIT_COMMAND_ERROR)
		end
	end
}

if commands[args.command] then
	commands[args.command](args.parameters, args.options)
	return
end

log_error(string.interpolate("unknown command: ${command}", { command = args.command }))
os.exit(EXIT_COMMAND_ERROR)
