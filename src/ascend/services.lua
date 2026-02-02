local aenv = require "ascend.internals.env"
local jobs = require("common.jobs")
local signal = require "os.signal"
local is_stop_requested = require "ascend.signal"
local isWindows = package.config:sub(1, 1) == "\\"
local log = require "ascend.log"

--- active - service is running
--- inactive - service was not yet started
--- failed - service failed -> exit code is not 0
--- stopped - service was stopped -> exit code was 0
--- stopping - service is stopping
--- to-be-started - service is waiting to be started - delayed start = later than boot but not counted into start count
---@alias AscendManagedServiceModuleStatusKind "active" | "inactive" | "failed" | "stopped" | "stopping" | "to-be-started"

---@class AscendManagedServiceModuleHealth
---@field state "healthy" | "unhealthy"
---@field isCheckInProgress boolean
---@field lastChecked number
---@field unhealthyCheckCount number

---@class AscendManagedServiceModule
---@field definition AscendServiceModuleDefinition
---@field state AscendManagedServiceModuleStatusKind
---@field process EliProcess?
---@field exit_code integer?
---@field started number?
---@field toBeStartedAt number?
---@field stopped number?
---@field manuallyStopped boolean
---@field restartCount number
---@field notifiedRestartsExhausted boolean?
---@field health AscendManagedServiceModuleHealth
---@field __output EliReadableStream?
---@field __output_file AscendRotatingLogFile?

---@class AscendManagedService
---@field modules table<string, AscendManagedServiceModule>
---@field source string

---@class AscendManagedServiceModuleStatus
---@field exit_code integer?
---@field state AscendManagedServiceModuleStatusKind
---@field started number?
---@field stopped number?

---@type table<string, AscendManagedService>
local managed_services = {}

local services = {}

---@param name string
---@return string
---@return string
local function name_to_service_module(name)
	local serviceName, moduleName = string.match(name, "^(.+):(.+)$")
	if not serviceName or not moduleName then
		return name, "all"
	end
	return serviceName, moduleName
end

---@param definition AscendServiceModuleDefinition
---@return AscendManagedServiceModule
local function new_managed_module(definition)
	return {
		definition = definition,
		state = "inactive",
		process = nil,
		exit_code = nil,
		started = nil,
		stopped = nil,
		manuallyStopped = false,
		restartCount = 0
	}
end

---Initializes the services module
---@return boolean
---@return string?
function services.init()
	log_info("loading services")
	local definitions, err = aenv.load_service_definitions()
	if not definitions then
		return false, err
	end

	for name, definition in pairs(definitions) do
		local modules = {}
		for moduleName, moduleDefinition in pairs(definition.modules) do
			modules[moduleName] = new_managed_module(moduleDefinition)
		end
		managed_services[name] = {
			modules = modules,
			source = definition.source
		}
	end
	log_info("loaded ${count} services", { count = #table.keys(managed_services) })
	return true
end

---Reloads the service definitions
---@return boolean
---@return string?
function services.reload()
	local definitions, err = aenv.load_service_definitions()
	if not definitions then
		log_error("failed to load service definitions: ${error}", { error = err })
		return false, definitions --[[@as string]]
	end

	for name, definition in pairs(definitions) do
		local service = managed_services[name] or {}
		local modules = service.modules or {}

		for moduleName, moduleDefinition in pairs(definition.modules) do
			local module = modules[moduleName]
			if not module then
				modules[moduleName] = new_managed_module(moduleDefinition)
			else
				module.definition = moduleDefinition
			end
		end
		managed_services[name] = {
			modules = modules,
			source = definition.source
		}
	end

	local to_remove = {}
	for name in pairs(managed_services) do
		if not definitions[name] then
			table.insert(to_remove, name)
		end
	end

	for _, name in ipairs(to_remove) do
		services.stop(name)
		managed_services[name] = nil
	end

	return true
end

---@param services string[]?
---@param extended boolean?
---@return table<string, string[]>
function services.list(services, extended)
	local list = {}
	for name, _ in pairs(managed_services) do
		if services and #services > 0 and not table.includes(services, name) then
			goto CONTINUE
		end
		list[name] = {}
		for moduleName, module in pairs(managed_services[name].modules) do
			if extended then
				list[name][moduleName] = {
					state = module.state,
					health = module.health.state,
					pid = module.process and module.process:get_pid(),
				}
			else
				table.insert(list[name], moduleName)
			end
		end
		::CONTINUE::
	end
	return list
end

---@param names string[]
---@return table<string, any>?, string?
function services.show(names)
	local result = {}
	for _, name in ipairs(names) do
		local service_name, module_name = name_to_service_module(name)
		local service = managed_services[service_name]
		if not service then
			local msg = string.interpolate("service ${name} not found", { name = service_name })
			return nil, msg
		end

		local modules = service.modules
		if module_name ~= "all" then
			modules = { [module_name] = service.modules[module_name] }
		end

		local modulesResult = {}
		for moduleName, module in pairs(modules) do
			modulesResult[moduleName] = module.definition
		end
		result[service_name] = modulesResult
	end
	return result
end

---@param names string[]
---@return table<string, { source: string, content: string }>?, string?
function services.cat(names)
	local result = {}
	for _, name in ipairs(names) do
		local service_name = name_to_service_module(name)
		local service = managed_services[service_name]
		if not service then
			local msg = string.interpolate("service ${name} not found", { name = service_name })
			return nil, msg
		end

		local source = service.source
		if type(source) ~= "string" then
			local msg = string.interpolate("service ${name} source not found", { name = service_name })
			return nil, msg
		end

		local content, err = fs.read_file(source)
		if not content then
			local msg = string.interpolate("failed to read ${source}: ${error}", { source = source, error = err })
			return nil, msg
		end

		result[service_name] = {
			source = source,
			content = content
		}
	end
	return result
end

---@class StartOptions
---@field manual boolean?
---@field is_boot boolean?

---@param module AscendManagedServiceModule
---@param options StartOptions?
---@return boolean
---@return string?
local function start_module(module, options)
	if module.state == "active" then
		return true
	end

	if type(options) ~= "table" then
		options = {}
	end

	local needsDirChange = type(module.definition.working_directory) == "string"
	local currentWorkingDir = needsDirChange and os.cwd()
	if needsDirChange then
		os.chdir(module.definition.working_directory)
	end

	if not options.manual and not options.is_boot then
		module.restartCount = module.restartCount + 1
	else -- if manually started, reset restart count
		module.restartCount = 0
	end

	if module.definition.user and isWindows then
		log_warn("user is not supported on windows, ignoring")
		module.definition.user = nil
	end

	local output = module.definition.log_file == "none" and "inherit" or "pipe"
	local process, err = proc.spawn(module.definition.executable, module.definition.args,
		{
			env = module.definition.environment,
			wait = false,
			stdio = {
				stdin = "ignore",
				output = output,
			},
			create_process_group = true,
			username = module.definition.user
		}) --[[@as EliProcess]]
	if needsDirChange then
		os.chdir(currentWorkingDir --[[@as string]])
	end
	if not process then
		return false, err --[[@as string]]
	end

	module.process = process
	module.state = "active"
	module.exit_code = nil
	module.started = os.time()
	module.stopped = nil
	module.manuallyStopped = false
	module.health = {
		state = "healthy",
		lastChecked = 0,
		unhealthyCheckCount = 0,
		isCheckInProgress = false
	}
	if module.definition.log_file ~= "none" then
		module.__output = process:get_stdout() -- stdout and stderr are combined because of `output = "pipe"`
		module.__output_file = module.__output_file or log.create_log_file(module.definition)
		module.__output_file:write(" -- service start --\n")
	end

	return true
end

---@param name string
---@param options StartOptions?
---@return boolean, string?
function services.start(name, options)
	if type(options) ~= "table" then
		options = {}
	end

	local service_name, module_name = name_to_service_module(name)
	local service = managed_services[service_name]
	if not service then
		local msg = string.interpolate("service ${name} not found", { name = service_name })
		return false, msg
	end

	local modulesToManage = module_name == "all" and service.modules or { [module_name] = service.modules[module_name] }
	local modulesToManageCount = #table.keys(modulesToManage)
	if modulesToManageCount == 0 then
		local msg = string.interpolate("module ${module} not found in service ${service}",
		{ module = module_name, service = service_name })
		return false, msg
	end

	-- ---@type string[]
	-- local failedModules = {}
	-- local startedModules = 0
	for module_name, managedModule in pairs(modulesToManage) do
		if options.is_boot then
			if not managedModule.definition.autostart then
				-- if we are only starting auto-start modules, skip this module
				goto CONTINUE
			end

			if type(managedModule.definition.start_delay) == "number" then
				managedModule.toBeStartedAt = os.time() + managedModule.definition.start_delay
				managedModule.state = "to-be-started"
				goto CONTINUE
			end
		end
	
		if managedModule.definition.working_directory and not fs.exists(managedModule.definition.working_directory) then
			log_warn("working directory for ${name}:${module} does not exist",
				{ name = service_name, module = module_name })
			goto CONTINUE
		end
		log_debug("starting ${name}:${module} - ${executable} from '${working_directory}'",
			{
				name = service_name,
				working_directory = managedModule.definition.working_directory,
				executable = managedModule.definition.executable,
				module = module_name
			})
		local ok, err = start_module(managedModule, options)
		if not ok then
			log_debug("failed to start ${name}:${module} (${executable}) from '${working_directory}' - ${error}",
				{
					name = service_name,
					working_directory = managedModule.definition.working_directory,
					executable = managedModule.definition.executable,
					module = module_name,
					error = err
				})
			log_warn("failed to start ${name}:${module}", { name = service_name, module = module_name })
		else
			log_info("${name}:${module} started", { name = service_name, module = module_name })
		end
		::CONTINUE::
	end

	return true
end

---@param module AscendManagedServiceModule
---@param exit_code integer
---@param manual boolean?
local function update_module_state_to_stopepd(module, exit_code, manual)
	module.state = "stopped"
	module.exit_code = exit_code
	module.process = nil
	module.stopped = os.time()
	module.manuallyStopped = manual == true

	log.collect_output(module) -- collect the last output
	module.__output_file:write(" -- service stop --\n")
	module.__output_file:close()
	module.__output_file = nil
end

---@param name string
---@param manual boolean?
---@return boolean, string?
function services.stop(name, manual)
	local service_name, module_name = name_to_service_module(name)
	local service = managed_services[service_name]
	if not service then
		local msg = string.interpolate("${name} not found", { name = service_name })
		return false, msg
	end

	local modulesToStop = module_name == "all" and service.modules or { [module_name] = service.modules[module_name] }
	local modulesToManageCount = #table.keys(modulesToStop)
	if modulesToManageCount == 0 then
		local msg =string.interpolate("module ${module} not found in service ${service}",
			{ module = module_name, service = service_name })
		return false, msg
	end

	local stopJobs = {}

	for module_name, module in pairs(modulesToStop) do
		if module.state ~= "active" then
			goto CONTINUE
		end

		log_debug("stopping ${service}:${module}", { service = service_name, module = module_name })
		module.state = "stopping"

		table.insert(stopJobs, coroutine.create(function()
			local group = module.process:get_group()
			local killTarget = group or module.process -- we kill group by default to kill all children
			if killTarget == nil then return end
			local signalSent, err, code = killTarget:kill(module.definition.stop_signal or signal.SIGTERM)
			if code == 3 and group ~= nil then
				killTarget = module.process
				if killTarget == nil then return end
				signalSent, err = killTarget:kill(module.definition.stop_signal or signal.SIGTERM)
			end

			local timeout = module.definition.stop_timeout or 10
			-- get date in seconds
			local startTime = os.time()
			while os.time() - startTime < timeout + 1 do
				coroutine.yield()
				local exit_code = module.process:wait(1, 1000)
				if exit_code >= 0 then
					update_module_state_to_stopepd(module, exit_code, manual)
					log_info("${service}:${module} stopped", { service = service_name, module = module_name })
					return
				end
				coroutine.yield()
				if not signalSent then
					-- if we haven't sent a signal yet, send a SIGKILL
					signalSent, err = killTarget:kill(signal.SIGKILL)
				end
			end

			if not signalSent then
				log_debug("failed to send signal to ${service}:${module} - ${error}",
					{ service = service_name, module = module_name, error = err })
			end

			log_debug("${service}:${module} did not stop in time, killing it",
				{ service = service_name, module = module_name })

			-- force termination
			killTarget:kill(signal.SIGKILL)
			local exit_code = module.process:wait(10, 1000)
			if exit_code >= 0 then
				update_module_state_to_stopepd(module, exit_code, manual)
				log_info("${service}:${module} stopped (killed)", { service = service_name, module = module_name })
				return
			end

			log_warn("failed to stop ${service}:${module}", { service = service_name, module = module_name })
		end))
		::CONTINUE::
	end

	jobs.run_queue(stopJobs)
	return true
end

function services.stop_all()
	return coroutine.create(function()
		log_info("stopping all services")
		local stopJobs = jobs.create_queue(jobs.array_to_array_of_params(table.keys(managed_services)), function(name)
			local ok, err = services.stop(name)
			if not ok then
				log_error(err --[[@as string]])
			end
		end)

		jobs.run_queue(stopJobs)
	end)
end

---@class RestartOptions: StartOptions

---@param name string
---@param options RestartOptions?
---@return boolean, string?
function services.restart(name, options)
	if type(options) ~= "table" then
		options = {}
	end
	local ok, err = services.stop(name)
	if not ok then
		log_error("failed to stop service ${name}: ${error}", { name = name, error = err })
		return false, err
	end
	local ok, err = services.start(name, options)
	if not ok then
		log_error("failed to start service ${name}: ${error}", { name = name, error = err })
		return false, err
	end
	return true
end

---@param name string
---@return table<string, AscendManagedServiceModuleStatus>|false
---@return string?
function services.status(name)
	local service = managed_services[name]
	if not service then
		local msg = string.interpolate("service ${name} not found", { name = name })
		return false, msg
	end

	local result = {}
	for moduleName, module in pairs(service.modules) do
		local hasHealthcheck = type(module.definition.healthcheck) == "table"

		result[moduleName] = {
			exit_code = module.exit_code,
			state = module.state,
			started = module.started,
			stopped = module.stopped,
			health = hasHealthcheck and module.state == "active" and module.health.state or nil
		}
	end

	return result
end

function services.logs(name)
	log_debug("getting service ${name} log file", { name = name })

	local service_name, module_name = name_to_service_module(name)
	local service = managed_services[service_name]
	if not service then
		return nil, string.interpolate("service ${name} not found", { name = service_name })
	end

	local modulesToGetLogsFor = module_name == "all" and service.modules or { [module_name] = service.modules[module_name] }
	local modulesToGetLogsForCount = #table.keys(modulesToGetLogsFor)
	if modulesToGetLogsForCount == 0 then
		return nil,
			string.interpolate("module ${module} not found in service ${service}",
				{ module = module_name, service = service_name })
	end

	local logFiles = {}
	for moduleName, module in pairs(modulesToGetLogsFor) do
		if module.__output_file then
			logFiles[moduleName] = module.__output_file:get_filename()
		end
	end
	return service_name, logFiles
end

function services.is_managed(name)
	local serviceName, moduleName = name_to_service_module(name)
	local service = managed_services[serviceName]
	if not service then
		return false
	end
	if moduleName == "all" then
		return true
	end
	return service.modules[moduleName] ~= nil
end

---@param start boolean?
---@return thread
function services.manage(start)
	if start then
		for name, _ in pairs(managed_services) do
			log_debug("starting service ${name}", { name = name })
			local ok, err = services.start(name, { is_boot = true })
			if not ok then
				log_error("failed to start service ${name}: ${error}", { name = name, error = err })
			end
		end
	end
	return coroutine.create(function()
		while not is_stop_requested() do
			local time = os.time()
			for service_name, service in pairs(managed_services) do
				for module_name, module in pairs(service.modules) do
					if module.state ~= "to-be-started" then -- the log dir may not be created yet
						log.collect_output(module)
					end

					if table.includes({ "stopping" }, module.state) then -- skip if modules is being managed by state like "stopping"
						goto CONTINUE
					end

					if module.state == "inactive" then -- modules which are not started automatically or manually
						goto CONTINUE
					end

					if module.state == "to-be-started" then
						if module.toBeStartedAt < time then
							local ok, err = start_module(module, { is_boot = true })
							if not ok then
								log_error("failed to start ${service}:${module} - ${error}",
									{ service = service_name, module = module_name, error = err })
							else
								log_debug("${service}:${module} started (delayed)",
									{ service = service_name, module = module_name })
							end
						end
						goto CONTINUE
					end

					if module.state == "active" then
						local exit_code = module.process:wait(1, 1000)
						if exit_code >= 0 then
							log_info("${service}:${module} exited with code ${code}",
								{ service = service_name, module = module_name, code = exit_code })
							module.exit_code = exit_code
							module.state = exit_code == 0 and "stopped" or "failed"
							module.process = nil
							module.stopped = time
						elseif module.health.state == "unhealthy" and module.definition.healthcheck.action == "restart" then
							log_debug("${service}:${module} is unhealthy", { service = service_name, module = module_name })
							services.stop(string.interpolate("${service}:${module}",
								{ service = service_name, module = module_name }))
						else
							goto CONTINUE -- if process is still running, skip the rest
						end
					end

					local stoppedAt = module.stopped or 0
					local timeToRestart = module.definition.restart_delay + stoppedAt < time
					local restartsExhausted = module.definition.restart ~= "always" and
						module.definition.restart_max_retries > 0 and
						module.restartCount >= module.definition.restart_max_retries
					if not module.manuallyStopped and timeToRestart and not restartsExhausted then
						local shouldStart = false
						if module.definition.restart == "always" or module.definition.restart == "on-exit" or
							(module.definition.restart == "on-success" and module.state == "stopped") or
							(module.definition.restart == "on-failure" and module.state == "failed") then
							shouldStart = true
						end
						if shouldStart then
							log_debug("restarting ${service}:${module}", { service = service_name, module = module_name })
							local ok, err = services.start(string.interpolate("${service}:${module}",
								{ service = service_name, module = module_name }))
							if not ok then
								log_error("failed to restart ${service}:${module} - ${error}",
									{ service = service_name, error = err })
							end
						end
					end
					if restartsExhausted and not module.notifiedRestartsExhausted then
						log_info("${service}:${module} has exhausted restarts",
							{ service = service_name, module = module_name })
						module.notifiedRestartsExhausted = true
					end
					::CONTINUE::
				end
			end
			coroutine.yield()
		end
	end)
end

---@param service_name string
---@param module_name string
---@param health AscendManagedServiceModuleHealth
---@param healthcheck_definition AscendHealthCheckDefinition
local function run_healthcheck(service_name, module_name, health, healthcheck_definition)
	return coroutine.create(function()
		if health.isCheckInProgress then
			return
		end
		local lastChecked = health.lastChecked
		local interval = healthcheck_definition.interval
		local timeToCheck = lastChecked + interval < os.time()
		if not timeToCheck then
			return
		end

		health.isCheckInProgress = true

		local timeout = healthcheck_definition.timeout
		local startTime = os.time()

		log_trace("running healthcheck ${name} for ${service}:${module}",
			{ name = healthcheck_definition.name, service = service_name, module = module_name })
		local proc, err = proc.spawn(path.combine(aenv.healthchecksDirectory, healthcheck_definition.name),
			{ stdio = "inherit" })
		if not proc then
			log_error("failed to run healthcheck for ${service}:${module} - ${error}",
				{ service = service_name, module = module_name, error = err })
			health.state = "unhealthy"
			health.lastChecked = os.time()
			health.isCheckInProgress = false
			return
		end

		while not is_stop_requested() and health.isCheckInProgress do
			if timeout > 0 and os.time() - startTime > timeout then
				log_info("healthcheck for ${service}:${module} timed out", { service = service_name, module = module_name })
				health.state = "unhealthy"
				health.lastChecked = os.time()
				health.isCheckInProgress = false
				break
			end

			local exit_code = proc --[[@as EliProcess]]:wait(1, 1000)
			if exit_code < 0 then -- in progress
				coroutine.yield()
				goto CONTINUE
			elseif exit_code == 0 then
				health.state = "healthy"
			elseif health.unhealthyCheckCount + 1 >= healthcheck_definition.retries then
				log_info("healthcheck for ${service}:${module} failed with exit code ${code}",
					{ service = service_name, module = module_name, code = exit_code })
				health.state = "unhealthy"
			else
				health.unhealthyCheckCount = health.unhealthyCheckCount + 1
			end

			health.lastChecked = os.time()
			health.isCheckInProgress = false
			::CONTINUE::
		end
	end)
end

---@return thread
function services.healthcheck()
	return coroutine.create(function()
		local healthCheckJobs = {}

		while not is_stop_requested() do
			for serviceName, service in pairs(managed_services) do
				for moduleName, module in pairs(service.modules) do
					if module.state ~= "active" then
						goto CONTINUE
					end
					local healthCheck = module.definition.healthcheck
					local started = module.started or 0

					if type(healthCheck) == "table" and started + healthCheck.delay < os.time() then
						local job = run_healthcheck(serviceName, moduleName, module.health, healthCheck)
						table.insert(healthCheckJobs, job)
					end
					::CONTINUE::
				end
			end
			coroutine.yield()

			local newJobs = {}
			for _, job in ipairs(healthCheckJobs) do
				if coroutine.status(job) ~= "dead" then
					table.insert(newJobs, job)
					coroutine.resume(job)
				end
			end
			healthCheckJobs = newJobs
			coroutine.yield()
		end
	end)
end

---@param strict boolean? -- if true, only return "healthy" if all services are healthy and active
---@return "healthy" | "unhealthy"
function services.get_ascend_health(strict)
	local allHealthy = true
	for _, service in pairs(managed_services) do
		for _, module in pairs(service.modules) do
			if strict and module.state ~= "active" then
				allHealthy = false
				break
			end
			if module.state == "active" and module.health.state == "unhealthy" then
				allHealthy = false
				break
			end
		end
		if not allHealthy then
			break
		end
	end
	return allHealthy and "healthy" or "unhealthy"
end

return services
