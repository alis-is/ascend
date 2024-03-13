local aenv = require "ascend.internals.env"
local services = require "ascend.services"

local init = {}

local function run_init_hook()
	if aenv.initScript ~= nil then
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
