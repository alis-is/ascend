local signal = require "os.signal"
local args = require "common.args"
local isUnix = package.config:sub(1, 1) == "/"

local defaultAEnv = {
	servicesDirectory = isUnix and "/etc/ascend/services" or "C:\\ascend\\services",
	ipcEndpoint = "/tmp/ascend.sock",
	logDirectory = isUnix and "/var/log/ascend" or "C:\\ascend\\logs",
}

local aenv = {
	servicesDirectory = args.options.services or
		env.get_env("ASCEND_SERVICES") or
		defaultAEnv.servicesDirectory,
	ipcEndpoint = args.options.socket or
		env.get_env("ASCEND_SOCKET") or
		defaultAEnv.ipcEndpoint,
	logDirectory = args.options["log-dir"] or
		env.get_env("ASCEND_LOGS") or
		defaultAEnv.logDirectory,
}

---@class AscendServiceDefinitionBase
---@field environment table<string, string>?
---@field working_directory string?
---@field stop_signal number?
---@field stop_timeout number?
---@field depends string[]? -- //TODO: implement
---@field restart "always" | "never" | "on-failure" | nil
---@field restart_delay number?
---@field restart_max_retries number?

---@class AscendServiceModuleDefinition: AscendServiceDefinitionBase
---@field executable string
---@field args string[]?

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
		local moduleInfo = { name = k }
		if type(v) ~= "table" then
			return false, string.interpolate("module ${name} must be an JSON object", moduleInfo)
		end

		if type(v.executable) ~= "string" then
			return false, string.interpolate("module ${name} - executable must be a string", moduleInfo)
		end

		if type(v.args) ~= "table" then
			return false, string.interpolate("module ${name} - args must be an array", moduleInfo)
		end

		if not table.is_array(v.depends) then
			return false, string.interpolate("module ${name} - depends must be an array", moduleInfo)
		end

		if type(v.restart) ~= "string" then
			return false, string.interpolate("module ${name} - restart must be a string", moduleInfo)
		end

		if not table.includes({ "always", "never", "on-failure" }, v.restart) then
			return false,
				string.interpolate("module ${name} - restart must be one of: always, never, on-failure", moduleInfo)
		end

		if type(v.restart_delay) ~= "number" then
			return false, string.interpolate("module ${name} - restart_delay must be a number", moduleInfo)
		end

		if type(v.restart_max_retries) ~= "number" then
			return false, string.interpolate("module ${name} - restart_max_retries must be a number", moduleInfo)
		end

		if v.stop_timeout and type(v.stop_timeout) ~= "number" then
			return false, string.interpolate("module ${name} - stop_timeout must be a number or undefined", moduleInfo)
		end

		if type(v.stop_signal) ~= "number" then
			return false, string.interpolate("module ${name} - stop_signal must be a number", moduleInfo)
		end

		if type(v.environment) ~= "table" then
			return false, string.interpolate("module ${name} - environment must be an JSON object", moduleInfo)
		end

		if type(v.working_directory) ~= "string" and type(v.working_directory) ~= "nil" then
			return false, string.interpolate("module ${name} - working_directory must be a string or undefined", moduleInfo)
		end

		if type(v.working_directory) == "string" and #v.working_directory == 0 then
			return false, string.interpolate("module ${name} - working_directory must not be empty", moduleInfo)
		end
	end

	return true
end

local serviceDefinitionDefaults = {
	args = {},
	environment = {},
	stop_signal = signal.SIGTERM,
	depends = {},
	restart = "always",
	restart_delay = 1,
	restart_max_retries = 5
}

---@param definition table
---@return AscendServiceDefinition
local function normalize_service_definition(definition)
	local normalized = util.merge_tables(definition, serviceDefinitionDefaults)
	normalized.args = table.map(normalized.args, tostring)
	if type(normalized.modules) ~= "table" then
		normalized.modules = {
			default = util.merge_tables({
				executable = normalized.executable,
				args = normalized.args,
			}, serviceDefinitionDefaults)
		}
		normalized.executable = nil
		normalized.args = nil
	end

	for id, module in pairs(normalized.modules) do
		local args = util.clone(module.args)
		module = util.merge_tables(module, {
			args = table.map(args, tostring),
			environment =  util.merge_tables(module.environment, normalized.environment),
			depends = table.map(module.depends or normalized.depends, tostring),
			restart = module.restart or normalized.restart,
			restart_delay = module.restart_delay or normalized.restart_delay,
			restart_max_retries = module.restart_max_retries or normalized.restart_max_retries,
			stop_signal = module.stop_signal or normalized.stop_signal,
			stop_timeout = module.stop_timeout or normalized.stop_timeout,
			working_directory = module.working_directory or normalized.working_directory,
		}, { overwrite = true, arrayMergeStrategy = "prefer-t1" })

		module = util.merge_tables(module, serviceDefinitionDefaults)
		normalized.modules[id] = module
	end
	

	return {
		modules = normalized.modules
	}
end

---@param name string
---@return AscendServiceDefinition?, string?
local function load_service_definition(name)
	local ok, def = fs.safe_read_file(name)
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

	local completeServiceDef = normalize_service_definition(serviceDef)
	local ok, err = validate_service_definition(completeServiceDef)
	if not ok then
		return nil, string.join_strings(" - ", "failed to validate service definition", err)
	end
	completeServiceDef.source = name
	return completeServiceDef
end

---@return table<string, AscendServiceDefinition>?, string?
function aenv.load_service_definitions()
	if fs.file_type(aenv.servicesDirectory) ~= "directory" then
		return nil, string.interpolate("path ${path} is not a directory", { path = aenv.servicesDirectory })
	end

	local defs = fs.read_dir(aenv.servicesDirectory, { recurse = false, returnFullPaths = true, asDirEntries = false }) --[=[@as string[]]=]

	---@type table<string, { definition: table, source: string }>
	local services = {}
	for _, def in ipairs(defs) do
		local name, ext = path.nameext(def)

		-- if name does not end with hjson skip it
		if ext ~= "hjson" then
			goto continue
		end
		local service, err = load_service_definition(def)
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
