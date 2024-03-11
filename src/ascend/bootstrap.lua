local aenv = require "ascend.internals.env"

local function bootstrap()
	if aenv.bootstrapScript ~= nil then
		-- if is lua file
		if aenv.bootstrapScript:sub(-4) == ".lua" then
			dofile(aenv.bootstrapScript)
		else -- if is shell script
			local ok, err = os.execute(aenv.bootstrapScript)
			if not ok then
				error("Failed to execute bootstrap script: " .. err)
			end
		end
	end
end

return bootstrap
