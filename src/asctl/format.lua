local is_tty = require "is_tty".is_stdout_tty()

local format = {}

local RESET_COLOR = string.char(27) .. "[0m"

local colorMap = {
	["success"] = string.char(27) .. "[32m",
	["debug"] = string.char(27) .. "[30;1m",
	["trace"] = string.char(27) .. "[30;1m",
	["info"] = string.char(27) .. "[36m",
	["warn"] = string.char(27) .. "[33m",
	["warning"] = string.char(27) .. "[33m",
	["error"] = string.char(27) .. "[31m",
}

---@param status table<string, AscendManagedServiceModuleStatus>
function format.status(status)
	if is_tty then
		-- // TODO: format nicely
		print(hjson.encode(status))
	else
		print(hjson.encode_to_json(status, { indent = false }))
	end
end

---@param status table<string, any>
function format.list(status)
	if is_tty then
		-- // TODO: format nicely
		print(hjson.encode(status))
	else
		print(hjson.encode_to_json(status, { indent = false }))
	end
end

---@param status table<string, any>
function format.show(status)
	if is_tty then
		-- // TODO: format nicely
		print(hjson.encode(status))
	else
		print(hjson.encode_to_json(status, { indent = false }))
	end
end

function format.default(data)
	if is_tty then
		print(hjson.encode(data))
	else
		print(hjson.encode_to_json(data, { indent = false }))
	end
end

return format