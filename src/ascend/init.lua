local aenv = require "ascend.internals.env"
local services = require "ascend.services"

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

	local paths = fs.read_dir(appsDir)
	for _, path in ipairs(paths) do
		if fs.file_type(path) ~= "directory" then
			if not os.execute(string.interpolate("ami --path ${path} --is-app-installed")) then
				os.execute(string.interpolate("ami --path ${path} setup"))
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
			local ok, err = os.execute(aenv.initScript)
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
