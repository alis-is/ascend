local aenv = require "ascend.internals.env"
local jobs = require("common.jobs")
local signal = require "os.signal"
local is_stop_requested = require "ascend.signal"
local isWindows = package.config:sub(1, 1) == "\\"

---@alias AscendManagedServiceModuleStatusKind "active" | "inactive" | "failed" | "stopped" | "stopping"

---@class AscendManagedServiceModuleHealth
---@field state "healthy" | "unhealthy"
---@field isCheckInProgress boolean
---@field lastChecked number
---@field unhealthyCheckCount number

---@class AscendManagedServiceModule
---@field definition AscendServiceModuleDefinition
---@field state AscendManagedServiceModuleStatusKind
---@field process EliProcess?
---@field exitCode integer?
---@field started number?
---@field stopped number?
---@field manuallyStopped boolean
---@field restartCount number
---@field notifiedRestartsExhausted boolean?
---@field health AscendManagedServiceModuleHealth

---@class AscendManagedService
---@field modules table<string, AscendManagedServiceModule>
---@field source string

---@class AscendManagedServiceModuleStatus
---@field exitCode integer?
---@field state AscendManagedServiceModuleStatusKind
---@field started number?
---@field stopped number?

---@type table<string, AscendManagedService>
local managedServices = {}

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
		exitCode = nil,
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
		managedServices[name] = {
			modules = modules,
			source = definition.source
		}
	end
	log_info("loaded ${count} services", { count = #table.keys(managedServices) })
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
		local service = managedServices[name] or {}
		local modules = service.modules or {}

		for moduleName, moduleDefinition in pairs(definition.modules) do
			local module = service.modules[moduleName]
			if not module then
				modules[moduleName] = new_managed_module(moduleDefinition)
			else
				module.definition = moduleDefinition
			end
		end
		managedServices[name] = {
			modules = modules,
			source = definition.source
		}
	end
	return true
end

---@return table<string, string[]>
function services.list()
	local list = {}
	for name, _ in pairs(managedServices) do
		list[name] = {}
		for moduleName, _ in pairs(managedServices[name].modules) do
			table.insert(list[name], moduleName)
		end
	end
	return list
end

---@param module AscendManagedServiceModule
---@param manualStart boolean?
---@return boolean
---@return string?
local function start_module(module, manualStart)
	if module.state == "active" then
		return true
	end

	local needsDirChange = type(module.definition.working_directory) == "string"
	local currentWorkingDir = needsDirChange and os.cwd()
	if needsDirChange then
		os.chdir(module.definition.working_directory)
	end

	if not manualStart then
		module.restartCount = module.restartCount + 1
	else -- if manually started, reset restart count
		module.restartCount = 0
	end

	if module.definition.user and isWindows then
		log_warn("user is not supported on windows, ignoring")
		module.definition.user = nil
	end

	local ok, process = proc.safe_spawn(module.definition.executable, module.definition.args,
		{
			env = module.definition.environment,
			wait = false,
			stdio = "inherit",
			createProcessGroup = true,
			username = module.definition.user
		}) --[[@as EliProcess]]
	if needsDirChange then
		os.chdir(currentWorkingDir --[[@as string]])
	end
	if not ok then
		return false, process --[[@as string]]
	end

	module.process = process
	module.state = "active"
	module.exitCode = nil
	module.started = os.time()
	module.stopped = nil
	module.manuallyStopped = false
	module.health = {
		state = "healthy",
		lastChecked = 0,
		unhealthyCheckCount = 0,
		isCheckInProgress = false
	}
	return true
end

---@param name string
---@param manualStart boolean?
---@return boolean, string?
function services.start(name, manualStart)
	local serviceName, moduleName = name_to_service_module(name)
	local service = managedServices[serviceName]
	if not service then
		return false, string.interpolate("service ${name} not found", { name = serviceName })
	end

	local modulesToManage = moduleName == "all" and service.modules or { moduleName = service.modules[moduleName] }
	local modulesToManageCount = #table.keys(modulesToManage)
	if modulesToManageCount == 0 then
		return false,
			string.interpolate("module ${module} not found in service ${service}",
				{ module = moduleName, service = serviceName })
	end

	---@type string[]
	local failedModules = {}
	for moduleName, managedModule in pairs(modulesToManage) do
		log_debug("starting ${name}:${module} - ${executable} from '${workingDirectory}'",
			{
				name = serviceName,
				workingDirectory = managedModule.definition.working_directory,
				executable = managedModule.definition.executable,
				module = moduleName
			})
		local ok, err = start_module(managedModule, manualStart)
		if not ok then
			table.insert(failedModules, moduleName)
			log_debug("failed to start ${name}:${module} (${executable}) from '${workingDirectory}' - ${error}",
				{
					name = serviceName,
					workingDirectory = managedModule.definition.working_directory,
					executable = managedModule.definition.executable,
					module = moduleName,
					error = err
				})
		end
	end

	if #failedModules > 0 then
		log_debug("failed to start ${count} of ${total} modules of ${name}",
			{ count = #failedModules, total = modulesToManageCount, name = serviceName })
		local resultMessage = #failedModules == 0 and "failed to start service ${name}" or
			"failed to start service ${name}:${modules}"
		return false,
			string.interpolate(resultMessage,
				{ name = serviceName, modules = string.join(",", table.unpack(failedModules)) })
	end
	log_info("${name} started", { name = name })

	return true
end

---@param name string
---@param manual boolean?
---@return boolean, string?
function services.stop(name, manual)
	log_debug("stopping service ${name}", { name = name })

	local serviceName, moduleName = name_to_service_module(name)
	local service = managedServices[serviceName]
	if not service then
		return false, string.interpolate("service ${name} not found", { name = serviceName })
	end

	local modulesToManage = moduleName == "all" and service.modules or { moduleName = service.modules[moduleName] }
	local modulesToManageCount = #table.keys(modulesToManage)
	if modulesToManageCount == 0 then
		return false,
			string.interpolate("module ${module} not found in service ${service}",
				{ module = moduleName, service = serviceName })
	end

	local stopJobs = {}

	---@type string[]
	local failedModules = {}
	for moduleName, managedModule in pairs(modulesToManage) do
		if managedModule.state ~= "active" then
			goto CONTINUE
		end

		managedModule.state = "stopping"

		table.insert(stopJobs, coroutine.create(function()
			local group = managedModule.process:get_group()
			local killTarget = group or managedModule.process -- we kill group by default to kill all children
			if killTarget == nil then return end
			local signalSent, err, code = killTarget:kill(managedModule.definition.stop_signal or signal.SIGTERM)
			if code == 3 and group ~= nil then
				killTarget = managedModule.process
				if killTarget == nil then return end
				signalSent, err = killTarget:kill(managedModule.definition.stop_signal or signal.SIGTERM)
			end

			local timeout = managedModule.definition.stop_timeout or 10
			-- get date in seconds
			local startTime = os.time()
			while os.time() - startTime < timeout + 1 do
				coroutine.yield()
				local exitCode = managedModule.process:wait(100, 1000) -- wait 100ms for process to exit
				if exitCode >= 0 then
					managedModule.state = "stopped"
					managedModule.exitCode = exitCode
					managedModule.process = nil
					managedModule.stopped = os.time()
					managedModule.manuallyStopped = manual == true
					log_debug("${service}:${module} stopped", { service = serviceName, module = moduleName })
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
					{ service = serviceName, module = moduleName, error = err })
			end

			log_debug("${service}:${module} did not stop in time, killing it",
				{ service = serviceName, module = moduleName })

			-- force termination
			killTarget:kill(signal.SIGKILL)
			local exitCode = managedModule.process:wait(100, 1000)
			if exitCode >= 0 then
				managedModule.state = "stopped"
				managedModule.exitCode = exitCode
				managedModule.process = nil
				managedModule.stopped = os.time()
				managedModule.manuallyStopped = manual == true
				log_debug("${service}:${module} killed", { service = serviceName, module = moduleName })
				return
			end

			table.insert(failedModules, moduleName)
		end))
		::CONTINUE::
	end

	jobs.run_queue(stopJobs)

	if #failedModules > 0 then
		log_debug("failed to stop ${count} of ${total} modules of ${name}",
			{ count = #failedModules, total = modulesToManageCount, name = serviceName })
		local resultMessage = #failedModules == 0 and "failed to stop service ${name}" or
			"failed to stop service ${name}:${modules}"
		return false,
			string.interpolate(resultMessage,
				{ name = serviceName, modules = string.join(",", table.unpack(failedModules)) })
	end
	log_info("${name} stopped", { name = name })

	return true
end

function services.stop_all()
	return coroutine.create(function()
		log_info("stopping all services")
		local stopJobs = jobs.create_queue(jobs.array_to_array_of_params(table.keys(managedServices)), function(name)
			local ok, err = services.stop(name)
			if not ok then
				log_error(err --[[@as string]])
			end
		end)

		jobs.run_queue(stopJobs)
	end)
end

---@param name string
---@param manual boolean?
---@return boolean, string?
function services.restart(name, manual)
	local ok, err = services.stop(name)
	if not ok then
		log_error("failed to stop service ${name}: ${error}", { name = name, error = err })
		return false, err
	end
	local ok, err = services.start(name, manual)
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
	local service = managedServices[name]
	if not service then
		return false, string.interpolate("service ${name} not found", { name = name })
	end

	local result = {}
	local collectedModules = {}
	for moduleName, module in pairs(service.modules) do
		result[moduleName] = {
			exitCode = module.exitCode,
			state = module.state,
			started = module.started,
			stopped = module.stopped,
		}
		table.insert(collectedModules, moduleName)
	end

	return result
end

function services.logs(name)
	-- // TODO: implement
end

function services.is_managed(name)
	local serviceName, moduleName = name_to_service_module(name)
	local service = managedServices[serviceName]
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
		for name, _ in pairs(managedServices) do
			log_debug("starting service ${name}", { name = name })
			local ok, err = services.start(name)
			if not ok then
				log_error("failed to start service ${name}: ${error}", { name = name, error = err })
			end
		end
	end
	return coroutine.create(function()
		while not is_stop_requested() do
			local time = os.time()
			for serviceName, service in pairs(managedServices) do
				for moduleName, module in pairs(service.modules) do
					if table.includes({ "stopping" }, module.state) then -- skip if modules is being managed by state like "stopping"
						goto CONTINUE
					end

					if module.state == "active" then
						local exitCode = module.process:wait(1, 1000)
						if exitCode >= 0 then
							log_info("${service}:${module} exited with code ${code}",
								{ service = serviceName, module = moduleName, code = exitCode })
							module.exitCode = exitCode
							module.state = exitCode == 0 and "stopped" or "failed"
							module.process = nil
							module.stopped = time
						elseif module.health.state == "unhealthy" and module.definition.healthcheck.action == "restart" then
							-- // TODO: improve, we should not use services.stop directly here
							log_debug("${service}:${module} is unhealthy", { service = serviceName, module = moduleName })
							services.stop(string.interpolate("${service}:${module}",
								{ service = serviceName, module = moduleName }))
						else
							goto CONTINUE -- if process is still running, skip the rest
						end
					end

					local stoppedAt = module.stopped or 0
					local timeToRestart = module.definition.restart_delay + stoppedAt < time
					local restartsExhausted = module.definition.restart_max_retries > 0 and
						module.restartCount >= module.definition.restart_max_retries

					if not module.manuallyStopped and timeToRestart and not restartsExhausted then
						local shouldStart = false
						if module.definition.restart == "always" or (module.definition.restart == "on-failure" and module.state == "failed") then
							shouldStart = true
						end
						if shouldStart then
							log_debug("restarting ${service}:${module}", { service = serviceName, module = moduleName })
							local ok, err = start_module(module)
							if not ok then
								log_error("failed to restart ${service}:${module} - ${error}",
									{ service = serviceName, error = err })
							end
						end
					end
					if restartsExhausted and not module.notifiedRestartsExhausted then
						log_info("${service}:${module} has exhausted restarts",
							{ service = serviceName, module = moduleName })
						module.notifiedRestartsExhausted = true
					end
					::CONTINUE::
				end
			end
			coroutine.yield()
		end
	end)
end

---@param serviceName string
---@param moduleName string
---@param health AscendManagedServiceModuleHealth
---@param healthcheckDefinition AscendHealthCheckDefinition
local function run_healthcheck(serviceName, moduleName, health, healthcheckDefinition)
	return coroutine.create(function()
		if health.isCheckInProgress then
			return
		end
		local lastChecked = health.lastChecked
		local interval = healthcheckDefinition.interval
		local timeToCheck = lastChecked + interval < os.time()
		if not timeToCheck then
			return
		end

		health.isCheckInProgress = true

		local timeout = healthcheckDefinition.timeout
		local startTime = os.time()

		log_trace("running healthcheck ${name} for ${service}:${module}",
			{ name = healthcheckDefinition.name, service = serviceName, module = moduleName })
		local ok, proc = proc.safe_spawn(path.combine(aenv.healthchecksDirectory, healthcheckDefinition.name),
			{ stdio = "inherit" })
		if not ok then
			log_error("failed to run healthcheck for ${service}:${module} - ${error}",
				{ service = serviceName, module = moduleName, error = proc })
			health.state = "unhealthy"
			health.lastChecked = os.time()
			health.isCheckInProgress = false
			return
		end

		while not is_stop_requested() and health.isCheckInProgress do
			if timeout > 0 and os.time() - startTime > timeout then
				log_info("healthcheck for ${service}:${module} timed out", { service = serviceName, module = moduleName })
				health.state = "unhealthy"
				health.lastChecked = os.time()
				health.isCheckInProgress = false
				break
			end

			local exitcode = proc:wait(1, 1000)
			if exitcode < 0 then -- in progress
				coroutine.yield()
				goto CONTINUE
			elseif exitcode == 0 then
				health.state = "healthy"
			elseif health.unhealthyCheckCount + 1 >= healthcheckDefinition.retries then
				log_info("healthcheck for ${service}:${module} failed with exit code ${code}",
					{ service = serviceName, module = moduleName, code = exitcode })
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

---@param start boolean?
---@return thread
function services.healthcheck()
	return coroutine.create(function()
		local healthCheckJobs = {}

		while not is_stop_requested() do
			for serviceName, service in pairs(managedServices) do
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

return services
