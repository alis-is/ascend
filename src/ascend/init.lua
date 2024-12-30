local aenv = require "ascend.internals.env"
local services = require "ascend.services"

local isWindows = package.config:sub(1, 1) == "\\"
local SILENT_REDIRECT = isWindows and "> NUL 2>&1" or ">/dev/null 2>&1"

local init = {}

local function ami_init()
	local appsDir = os.getenv("ASCEND_APPS")
	if not appsDir then
		appsDir = path.combine(path.dir(aenv.servicesDirectory), "apps")
	end
	fs.mkdirp(appsDir)

	local initDir = os.getenv("APPS_BOOTSTRAP")
	if not initDir then
		error("APPS_BOOTSTRAP is not set")
	end

	fs.copy(initDir, appsDir, { overwrite = false })

	local paths = fs.read_dir(appsDir, { return_full_paths = true })
	for _, path in ipairs(paths) do
		if type(path) == "string" and fs.file_type(path) == "directory" then
			local isInstalled = os.execute(string.interpolate("ami --path=${path} --is-app-installed ${redirect}", { path = path, redirect = SILENT_REDIRECT }))
			if not isInstalled then
				if not os.execute(string.interpolate("ami --path=${path} setup", { path = path })) then
					error("Failed to setup app: " .. path)
				end
			else
				if not os.execute(string.interpolate("ami --path=${path} setup --configure", { path = path })) then
					error("Failed to configure app: " .. path)
				end
			end
		end
	end
end

local commonInitStrategies = {
	ami = ami_init
}

local function run_init_hook()
	fs.mkdirp(aenv.logDirectory)
	fs.mkdirp(aenv.servicesDirectory)
	fs.mkdirp(aenv.healthchecksDirectory)

	if aenv.initScript ~= nil then
		-- if is common init strategy
		if commonInitStrategies[aenv.initScript] then
			commonInitStrategies[aenv.initScript]()
			return
		end

		-- if is lua file
		if aenv.initScript:sub(-4) == ".lua" then
			dofile(aenv.initScript)
		else -- if is shell script
			-- skip options and pass through arguments
			local args = {}
			local lastOptionAt = 0
			for i, arg in ipairs(arg) do
				if arg:sub(1, 1) ~= "-" then
					break
				end
				lastOptionAt = i
			end
			for i = lastOptionAt + 1, #arg do
				table.insert(args, arg[i])
			end

			local ok, err = os.execute(aenv.initScript .. " " .. string.join(" ", args)) -- we pass through arguments to init script
			if not ok then
				error("Failed to execute init script: " .. err)
			end
		end
	end
end

function init.run()
	run_init_hook()

	local ok, err = services.init()
	if not ok then
		log_error("failed to initialize services: ${error}", { error = err })
		os.exit(EXIT_FAILED_TO_LOAD_SERVICES)
	end
end

return init
