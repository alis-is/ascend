local signal = require "os.signal"
local args = require "common.args"
local input = require "common.input"
local isUnix = package.config:sub(1, 1) == "/"

local defaultAEnv = {
	services_directory = isUnix and "/etc/ascend/services" or "C:\\ascend\\services",
	healthchecksDirectory = isUnix and "/etc/ascend/healthchecks" or "C:\\ascend\\healthchecks",
	ipcEndpoint = "/tmp/ascend.sock",
	logDirectory = isUnix and "/var/log/ascend" or "C:\\ascend\\logs",
	initScript = nil --[[@as string?]]
}

local aenv = util.merge_tables({
	services_directory = args.options.services or env.get_env("ASCEND_SERVICES"),
	healthchecksDirectory = args.options.healthchecks or env.get_env("ASCEND_HEALTHCHECKS"),
	ipcEndpoint = args.options.socket or env.get_env("ASCEND_SOCKET"),
	logDirectory = args.options["log-dir"] or env.get_env("ASCEND_LOGS"),
	initScript = args.options["init"] or env.get_env("ASCEND_INIT")
}, defaultAEnv)

---@class AscendHealthCheckDefinition
---@field name string
---@field interval number
---@field timeout number
---@field retries number
---@field delay number
---@field action "restart" | "none"

---@class AscendServiceDefinitionBase
---@field environment table<string, string>?
---@field working_directory string?
---@field stop_signal number?
---@field stop_timeout number?
---@field depends string[]? -- //TODO: implement
---@field autostart boolean?
---@field start_delay number?
---@field restart "always" | "never" | "on-failure" | "on-success" | "on-exit" | nil
---@field restart_delay number?
---@field restart_max_retries number?
---@field healthcheck AscendHealthCheckDefinition?
---@field user string?
---@field log_file string | "none" | nil
---@field log_rotate boolean
---@field log_max_size number
---@field log_max_files number

---@class AscendServiceModuleDefinition: AscendServiceDefinitionBase
---@field executable string
---@field args string[]?
---@field healthcheck AscendHealthCheckDefinition?

---@class AscendRawServiceDefinition : AscendServiceModuleDefinition
---@field modules table<string, AscendServiceModuleDefinition>

---@class AscendServiceDefinition
---@field modules table<string, AscendServiceModuleDefinition>
---@field source string

---@param definition AscendServiceDefinition
---@return boolean, string?
local function validate_service_definition(definition)
	if type(definition.modules) ~= "table" or table.is_array(definition.modules) then
		return false, "modules must be an JSON object"
	end

	for k, v in pairs(definition.modules) do
		if k == "all" then
			return false, "module name 'all' is reserved"
		end
		local module_info = { name = k }
		if type(v) ~= "table" then
			local msg = string.interpolate("module ${name} must be an JSON object", module_info)
			return false, msg
		end

		if type(v.executable) ~= "string" then
			local msg = string.interpolate("module ${name} - executable must be a string", module_info)
			return false, msg
		end

		if type(v.args) ~= "table" then
			local msg = string.interpolate("module ${name} - args must be an array", module_info)
			return false, msg
		end

		if not table.is_array(v.depends) then
			local msg = string.interpolate("module ${name} - depends must be an array", module_info)
			return false, msg
		end

		if type(v.restart) ~= "string" then
			local msg = string.interpolate("module ${name} - restart must be a string", module_info)
			return false, msg
		end

		if not table.includes({ "always", "never", "on-failure", "on-success", "on-exit" }, v.restart) then
			local msg = string.interpolate("module ${name} - restart must be one of: always, never, on-failure, on-success", module_info)
			return false, msg
		end

		if type(v.restart_delay) ~= "number" then
			local msg = string.interpolate("module ${name} - restart_delay must be a number", module_info)
			return false, msg
		end

		if type(v.restart_max_retries) ~= "number" then
			local msg = string.interpolate("module ${name} - restart_max_retries must be a number", module_info)
			return false, msg
		end

		if v.stop_timeout and type(v.stop_timeout) ~= "number" then
			local msg = string.interpolate("module ${name} - stop_timeout must be a number or undefined", module_info)
			return false, msg
		end

		if type(v.stop_signal) ~= "number" then
			local msg = string.interpolate("module ${name} - stop_signal must be a number", module_info)
			return false, msg
		end

		if type(v.environment) ~= "table" then
			local msg = string.interpolate("module ${name} - environment must be an JSON object", module_info)
			return false, msg
		end

		if type(v.working_directory) ~= "string" and type(v.working_directory) ~= "nil" then
			local msg = string.interpolate("module ${name} - working_directory must be a string or undefined", module_info)
			return false, msg
		end

		if type(v.working_directory) == "string" and #v.working_directory == 0 then
			local msg = string.interpolate("module ${name} - working_directory must not be empty", module_info)
			return false, msg
		end

		if type(v.log_file) == "string" and path.isabs(v.log_file) then
			local dir = path.dir(v.log_file)
			if not fs.exists(dir) then
				local msg = string.interpolate("module ${name} - log_file directory ${dir} does not exist",
					{ name = k, dir = dir })
				return false, msg
			end
		end

		if type(v.log_rotate) ~= "boolean" then
			local msg = string.interpolate("module ${name} - log_rotate must be a boolean", module_info)
			return false, msg
		end

		if type(v.log_max_files) ~= "number" then
			local msg = string.interpolate("module ${name} - log_max_files must be a number", module_info)
			return false, msg
		elseif v.log_max_files < 0 then
			local msg = string.interpolate("module ${name} - log_max_files must be greater than 0", module_info)
			return false, msg
		end

		local max_log_file_size = input.parse_size_value(tostring(v.log_max_size))
		if type(max_log_file_size) ~= "number" then
			local msg = string.interpolate("module ${name} - log_max_size must be a number (accepts k, m, g suffixes)",
				module_info)
			return false, msg
		elseif max_log_file_size < 1024 then
			local msg = string.interpolate("module ${name} - log_max_size must be greater than 1KB", module_info)
			return false, msg
		end

		if type(v.healthcheck) == "table" then -- healthchecks are optional so validate only if defined
			if type(v.healthcheck.name) ~= "string" then
				local msg = string.interpolate("module ${name} - healthcheck.name must be a string", module_info)
				return false, msg
			end

			if type(v.healthcheck.action) == "string" and not table.includes({ "restart", "none" }, v.healthcheck.action) then
				local msg = string.interpolate("module ${name} - healthcheck.action must be one of: restart, none", module_info)
				return false, msg
			end

			if type(v.healthcheck.interval) ~= "number" then
				local msg = string.interpolate("module ${name} - healthcheck.interval must be a number", module_info)
				return false, msg
			end

			if type(v.healthcheck.timeout) ~= "number" then
				local msg = string.interpolate("module ${name} - healthcheck.timeout must be a number", module_info)
				return false, msg
			end

			if type(v.healthcheck.retries) ~= "number" then
				local msg = string.interpolate("module ${name} - healthcheck.retries must be a number", module_info)
				return false, msg
			end
			if v.healthcheck.retries <= 0 then
				local msg = string.interpolate("module ${name} - healthcheck.retries must be greater than 0", module_info)
				return false, msg
			end
			if type(v.healthcheck.delay) ~= "number" then
				local msg = string.interpolate("module ${name} - healthcheck.delay must be a number", module_info)
				return false, msg
			end

			if v.healthcheck.interval < 1 then
				local msg = string.interpolate("module ${name} - healthcheck.interval must be greater than 0", module_info)
				return false, msg
			end
		end
	end

	return true
end

---@type AscendServiceDefinitionBase
local serviceDefinitionDefaults = {
	args = {},
	environment = {},
	stop_signal = signal.SIGTERM,
	depends = {},
	autostart = true,
	restart = "on-exit",
	restart_delay = 1,
	restart_max_retries = 5,
	log_rotate = true,
	log_max_size = tonumber(os.getenv("ASCEND_LOG_MAX_FILE_SIZE")) or 1024 * 1024 * 10,
	log_max_files = tonumber(os.getenv("ASCEND_LOG_MAX_FILE_COUNT")) or 5
}

local serviceDefinitionHealthCheckDefaults = {
	interval = 30,
	timeout = 30,
	retries = 1,
	delay = 30,
	action = "none"
}

---@param name string
---@param definition table
---@return AscendServiceDefinition
local function normalize_service_definition(name, definition)
	local normalized = util.merge_tables(definition, serviceDefinitionDefaults)
	normalized.args = table.map(normalized.args, tostring)
	if type(normalized.modules) ~= "table" then
		normalized.modules = {
			default = util.merge_tables({
				executable = normalized.executable,
				args = normalized.args,
				depends = normalized.depends,
				autostart = normalized.autostart,
				start_delay = normalized.start_delay,
				restart = normalized.restart,
				restart_delay = normalized.restart_delay,
				restart_max_retries = normalized.restart_max_retries,
				stop_signal = normalized.stop_signal,
				stop_timeout = normalized.stop_timeout,
				working_directory = normalized.working_directory,
				user = normalized.user,
				environment = normalized.environment,
				healthcheck = normalized.healthcheck,
				log_file = normalized.log_file or path.combine(name, "default.log"),
				log_rotate = normalized.log_rotate,
				log_max_size = normalized.log_max_size,
				log_max_files = normalized.log_max_files
			}, serviceDefinitionDefaults)
		}
		normalized.executable = nil
		normalized.args = nil
	end

	for id, module in pairs(normalized.modules) do
		local args = util.clone(module.args)
		module = util.merge_tables(module, {
			args = table.map(args, tostring),
			environment = util.merge_tables(module.environment, normalized.environment),
			depends = table.map(module.depends or normalized.depends or {}, tostring),
			autostart = module.autostart or normalized.autostart,
			start_delay = module.start_delay or normalized.start_delay,
			restart = module.restart or normalized.restart,
			restart_delay = module.restart_delay or normalized.restart_delay,
			restart_max_retries = module.restart_max_retries or normalized.restart_max_retries,
			stop_signal = module.stop_signal or normalized.stop_signal,
			stop_timeout = module.stop_timeout or normalized.stop_timeout,
			working_directory = module.working_directory or normalized.working_directory,
			user = module.user or normalized.user,
			healthcheck = module.healthcheck or normalized.healthcheck,
			log_file = module.log_file or path.combine(name, id .. ".log"),
			log_rotate = module.log_rotate or normalized.log_rotate,
			log_max_size = module.log_max_size or normalized.log_max_size,
			log_max_files = module.log_max_files or normalized.log_max_files
		}, { overwrite = true, array_merge_strategy = "prefer-t1" })

		module = util.merge_tables(module, serviceDefinitionDefaults)
		if type(module.healthcheck) == "table" then
			module.healthcheck = util.merge_tables(module.healthcheck, serviceDefinitionHealthCheckDefaults)
		end

		normalized.modules[id] = module
	end

	return {
		modules = normalized.modules
	}
end

---@param name string
---@param filename string
---@return AscendServiceDefinition?, string?
local function load_service_definition(name, filename)
	local ok, def = fs.safe_read_file(filename)
	if not ok then
		return nil, def
	end
	local ok, serviceDef = hjson.safe_parse(def)
	if not ok then
		return nil, string.join_strings(" - ", "failed to decode service definition", serviceDef)
	end

	if type(serviceDef) ~= "table" and not table.is_array(serviceDef) then
		return nil, "service definition must be an JSON object"
	end

	local completeServiceDef = normalize_service_definition(name, serviceDef)
	local ok, err = validate_service_definition(completeServiceDef)
	if not ok then
		return nil, string.join_strings(" - ", "failed to validate service definition", err)
	end
	completeServiceDef.source = filename
	return completeServiceDef
end

---@return table<string, AscendServiceDefinition>?, string?
function aenv.load_service_definitions()
	if fs.file_type(aenv.services_directory) ~= "directory" then
		local msg = string.interpolate("path ${path} is not a directory", { path = aenv.services_directory })
		return nil, msg
	end

	local defs = fs.read_dir(aenv.services_directory, { recurse = false, return_full_paths = true, as_dir_entries = false }) --[=[@as string[]]=]

	---@type table<string, { definition: table, source: string }>
	local services = {}
	for _, def in ipairs(defs) do
		local name, ext = path.nameext(def)

		-- if name does not end with hjson skip it
		if ext ~= "hjson" then
			goto continue
		end
		local service, err = load_service_definition(name, def)
		if not service then
			log_error("failed to load service ${name}: ${error}", { name = name, error = err })
			goto continue
		end
		services[name] = service
		::continue::
	end
	return services
end

return aenv
