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

---@return AscendManagedServiceModuleHealth
local function new_module_health_state()
	return {
		state = "healthy",
		lastChecked = 0,
		unhealthyCheckCount = 0,
		isCheckInProgress = false
	}
end

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

---@param service_name string
---@param module_name string
---@return string
local function service_module_name(service_name, module_name)
	return service_name .. ":" .. module_name
end

---@param current_service_name string
---@param dependency_name string
---@return string
local function resolve_dependency_name(current_service_name, dependency_name)
	local currentService = managed_services[current_service_name]
	local dependencyServiceName, dependencyModuleName = name_to_service_module(dependency_name)
	if dependencyModuleName ~= "all" then
		return service_module_name(dependencyServiceName, dependencyModuleName)
	end
	if currentService and currentService.modules[dependency_name] then
		return service_module_name(current_service_name, dependency_name)
	end
	return dependency_name
end

---@param name string
---@return boolean
local function is_target_active(name)
	local service_name, module_name = name_to_service_module(name)
	local service = managed_services[service_name]
	if not service then
		return false
	end

	if module_name == "all" then
		for _, module in pairs(service.modules) do
			if module.state ~= "active" then
				return false
			end
		end
		return true
	end

	local module = service.modules[module_name]
	return module ~= nil and module.state == "active"
end

---@param service_name string
---@param module_name string
---@param module AscendManagedServiceModule
---@return string[]?, string?
local function get_module_dependencies(service_name, module_name, module)
	local dependencies = {}
	local seen = {}
	for _, dependency_name in ipairs(module.definition.depends or {}) do
		local normalizedDependencyName = resolve_dependency_name(service_name, dependency_name)
		if not services.is_managed(normalizedDependencyName) then
			local msg = string.interpolate("dependency ${dependency} for ${service}:${module} not found", {
				dependency = dependency_name,
				service = service_name,
				module = module_name,
			})
			return nil, msg
		end
		if not seen[normalizedDependencyName] then
			table.insert(dependencies, normalizedDependencyName)
			seen[normalizedDependencyName] = true
		end
	end
	return dependencies
end

---@param dependency_names string[]
---@return boolean, string?
local function dependencies_are_active(dependency_names)
	local inactiveDependencies = {}
	for _, dependency_name in ipairs(dependency_names) do
		if not is_target_active(dependency_name) then
			table.insert(inactiveDependencies, dependency_name)
		end
	end

	if #inactiveDependencies > 0 then
		return false, table.concat(inactiveDependencies, ", ")
	end

	return true
end

---@param module AscendManagedServiceModule
---@param options StartOptions
local function schedule_module_start(module, options)
	local scheduledAt = os.time()
	if options.is_boot and type(module.definition.start_delay) == "number" then
		scheduledAt = scheduledAt + module.definition.start_delay
	end

	if module.state == "to-be-started" and type(module.toBeStartedAt) == "number" then
		local currentScheduledAt = module.toBeStartedAt --[[@as number]]
		scheduledAt = math.min(currentScheduledAt, scheduledAt)
	end

	module.toBeStartedAt = scheduledAt
	module.state = "to-be-started"
end

---@param dependency_name string
---@param target_name string
---@return boolean
local function dependency_matches_target(dependency_name, target_name)
	local dependencyServiceName, dependencyModuleName = name_to_service_module(dependency_name)
	local targetServiceName, targetModuleName = name_to_service_module(target_name)
	if dependencyServiceName ~= targetServiceName then
		return false
	end

	return dependencyModuleName == "all" or targetModuleName == "all" or dependencyModuleName == targetModuleName
end

---@param target_name string
---@return string[]
local function get_reverse_dependencies(target_name)
	local dependents = {}
	for service_name, service in pairs(managed_services) do
		for module_name, module in pairs(service.modules) do
			local currentModuleName = service_module_name(service_name, module_name)
			if currentModuleName == target_name then
				goto CONTINUE
			end

			local dependencies = get_module_dependencies(service_name, module_name, module)
			if not dependencies then
				goto CONTINUE
			end

			for _, dependency_name in ipairs(dependencies) do
				if dependency_matches_target(dependency_name, target_name) then
					table.insert(dependents, currentModuleName)
					break
				end
			end

			::CONTINUE::
		end
	end
	return dependents
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
		restartCount = 0,
		health = new_module_health_state()
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
				local hasHealthcheck = type(module.definition.healthcheck) == "table"
				list[name][moduleName] = {
					state = module.state,
					health = hasHealthcheck and module.health.state or nil,
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

---@class StartOptions
---@field manual boolean?
---@field is_boot boolean?
---@field force boolean?

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
	module.toBeStartedAt = nil
	module.manuallyStopped = false
	module.health = new_module_health_state()
	if module.definition.log_file ~= "none" then
		module.__output = process:get_stdout() -- stdout and stderr are combined because of `output = "pipe"`
		module.__output_file = module.__output_file or log.create_log_file(module.definition)
		module.__output_file:write(" -- service start --\n")
	end

	return true
end

---@param service_name string
---@param module_name string
---@param managedModule AscendManagedServiceModule
---@param options StartOptions?
---@param scheduled boolean?
---@return boolean, string?
local function try_start_managed_module(service_name, module_name, managedModule, options, scheduled)
	if managedModule.state == "active" then
		return true
	end

	if managedModule.definition.working_directory and not fs.exists(managedModule.definition.working_directory) then
		local err = string.interpolate("working directory for ${name}:${module} does not exist", {
			name = service_name,
			module = module_name,
		})
		log_warn(err)
		return false, err
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
		return false, err
	end

	if scheduled and type(managedModule.definition.start_delay) == "number" then
		log_debug("${service}:${module} started (delayed)", { service = service_name, module = module_name })
	else
		log_info("${name}:${module} started", { name = service_name, module = module_name })
	end

	return true
end

---@param name string
---@param options StartOptions?
---@param visiting table<string, boolean>?
---@return boolean, string?
local function start_target(name, options, visiting)
	if type(options) ~= "table" then
		options = {}
	end
	visiting = visiting or {}

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

	for current_module_name, managedModule in pairs(modulesToManage) do
		if options.is_boot and not options.force and not managedModule.definition.autostart then
			goto CONTINUE
		end

		local currentModuleName = service_module_name(service_name, current_module_name)
		if visiting[currentModuleName] then
			local msg = string.interpolate("circular dependency detected for ${name}", { name = currentModuleName })
			return false, msg
		end

		visiting[currentModuleName] = true
		local dependencies, err = get_module_dependencies(service_name, current_module_name, managedModule)
		if not dependencies then
			visiting[currentModuleName] = nil
			return false, err
		end

		for _, dependency_name in ipairs(dependencies) do
			local ok, dependencyErr = start_target(dependency_name, {
				manual = options.manual,
				is_boot = options.is_boot,
				force = true,
			}, visiting)
			if not ok then
				visiting[currentModuleName] = nil
				return false, dependencyErr
			end
		end
		visiting[currentModuleName] = nil

		local dependenciesReady, inactiveDependencies = dependencies_are_active(dependencies)
		if not dependenciesReady then
			if options.is_boot then
				schedule_module_start(managedModule, options)
				goto CONTINUE
			end

			local err = string.interpolate("dependencies for ${name} are not active: ${dependencies}", {
				name = currentModuleName,
				dependencies = inactiveDependencies,
			})
			return false, err
		end

		if options.is_boot and type(managedModule.definition.start_delay) == "number" then
			schedule_module_start(managedModule, options)
			goto CONTINUE
		end

		local ok, err = try_start_managed_module(service_name, current_module_name, managedModule, options)
		if not ok then
			return false, err
		end

		::CONTINUE::
	end

	return true
end

---@param module AscendManagedServiceModule
---@param exit_code integer
---@param manual boolean?
local function update_module_state_to_stopped(module, exit_code, manual)
	module.state = "stopped"
	module.exit_code = exit_code
	module.process = nil
	module.stopped = os.time()
	module.manuallyStopped = manual == true

	log.collect_output(module) -- collect the last output
	if module.__output_file then
		module.__output_file:write(" -- service stop --\n")
		module.__output_file:close()
	end
	module.__output_file = nil
	module.__output = nil
end

---@param name string
---@param manual boolean?
---@param visited table<string, boolean>?
---@return boolean, string?
local function stop_target(name, manual, visited)
	visited = visited or {}
	if visited[name] then
		return true
	end
	visited[name] = true

	for _, dependent_name in ipairs(get_reverse_dependencies(name)) do
		local ok, err = stop_target(dependent_name, manual, visited)
		if not ok then
			return false, err
		end
	end

	local service_name, module_name = name_to_service_module(name)
	local service = managed_services[service_name]
	if not service then
		local msg = string.interpolate("${name} not found", { name = service_name })
		return false, msg
	end

	local modulesToStop = module_name == "all" and service.modules or { [module_name] = service.modules[module_name] }
	local modulesToManageCount = #table.keys(modulesToStop)
	if modulesToManageCount == 0 then
		local msg = string.interpolate("module ${module} not found in service ${service}",
			{ module = module_name, service = service_name })
		return false, msg
	end

	local stopJobs = {}

	for current_module_name, module in pairs(modulesToStop) do
		if module.state ~= "active" then
			goto CONTINUE
		end

		log_debug("stopping ${service}:${module}", { service = service_name, module = current_module_name })
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
			local startTime = os.time()
			while os.time() - startTime < timeout + 1 do
				coroutine.yield()
				local exit_code = module.process:wait(1, 1000)
				if exit_code >= 0 then
					update_module_state_to_stopped(module, exit_code, manual)
					log_info("${service}:${module} stopped", { service = service_name, module = current_module_name })
					return
				end
				coroutine.yield()
				if not signalSent then
					signalSent, err = killTarget:kill(signal.SIGKILL)
				end
			end

			if not signalSent then
				log_debug("failed to send signal to ${service}:${module} - ${error}",
					{ service = service_name, module = current_module_name, error = err })
			end

			log_debug("${service}:${module} did not stop in time, killing it",
				{ service = service_name, module = current_module_name })

			killTarget:kill(signal.SIGKILL)
			local exit_code = module.process:wait(10, 1000)
			if exit_code >= 0 then
				update_module_state_to_stopped(module, exit_code, manual)
				log_info("${service}:${module} stopped (killed)", { service = service_name, module = current_module_name })
				return
			end

			log_warn("failed to stop ${service}:${module}", { service = service_name, module = current_module_name })
		end))
		::CONTINUE::
	end

	jobs.run_queue(stopJobs)
	return true
end

---@param name string
---@param options StartOptions?
---@return boolean, string?
function services.start(name, options)
	return start_target(name, options, {})
end

---@param name string
---@param manual boolean?
---@return boolean, string?
function services.stop(name, manual)
	return stop_target(name, manual, {})
end

function services.stop_all()
	return coroutine.create(function()
		log_info("stopping all services")
		local visited = {}
		for name in pairs(managed_services) do
			local ok, err = stop_target(name, nil, visited)
			if not ok then
				log_error(err --[[@as string]])
			end
		end
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
						if (module.toBeStartedAt or 0) < time then
							local dependencies, err = get_module_dependencies(service_name, module_name, module)
							if not dependencies then
								log_error("failed to start ${service}:${module} - ${error}",
									{ service = service_name, module = module_name, error = err })
								module.state = "inactive"
								module.toBeStartedAt = nil
								goto CONTINUE
							end

							local dependenciesReady = dependencies_are_active(dependencies)
							if not dependenciesReady then
								goto CONTINUE
							end

							local ok, err = try_start_managed_module(service_name, module_name, module, { is_boot = true }, true)
							if not ok then
								log_error("failed to start ${service}:${module} - ${error}",
									{ service = service_name, module = module_name, error = err })
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
						elseif type(module.definition.healthcheck) == "table" and module.health.state == "unhealthy" and module.definition.healthcheck.action == "restart" then
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
