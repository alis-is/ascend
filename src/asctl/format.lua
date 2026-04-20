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

---@param map table<string, any>
---@return string[]
local function sorted_keys(map)
	local keys = table.keys(map)
	table.sort(keys)
	return keys
end

---@param value any
---@return string
local function stringify(value)
	if value == nil then
		return "-"
	end
	if type(value) == "boolean" then
		return value and "true" or "false"
	end
	return tostring(value)
end

---@param text string
---@param color string?
---@return string
local function colorize(text, color)
	if not is_tty or color == nil then
		return text
	end
	return color .. text .. RESET_COLOR
end

---@param value any
---@param color string?
---@return { text: string, color: string? }
local function cell(value, color)
	return {
		text = stringify(value),
		color = color,
	}
end

---@param cell_value { text: string, color: string? }
---@param width integer
---@return string
local function render_cell(cell_value, width)
	local padded = cell_value.text .. string.rep(" ", math.max(0, width - #cell_value.text))
	return colorize(padded, cell_value.color)
end

---@param headers string[]
---@param rows table[]
---@return string
local function build_table(headers, rows)
	local widths = {}
	for i, header in ipairs(headers) do
		widths[i] = #header
	end

	for _, row in ipairs(rows) do
		for i, value in ipairs(row) do
			local cell_value = type(value) == "table" and value or cell(value)
			if #cell_value.text > widths[i] then
				widths[i] = #cell_value.text
			end
		end
	end

	local header_row = {}
	local divider_row = {}
	for i, header in ipairs(headers) do
		header_row[i] = header .. string.rep(" ", widths[i] - #header)
		divider_row[i] = string.rep("-", widths[i])
	end

	local lines = {
		table.concat(header_row, "  "),
		table.concat(divider_row, "  "),
	}

	for _, row in ipairs(rows) do
		local rendered = {}
		for i = 1, #headers do
			local value = row[i]
			local cell_value = type(value) == "table" and value or cell(value)
			rendered[i] = render_cell(cell_value, widths[i])
		end
		table.insert(lines, table.concat(rendered, "  "))
	end

	return table.concat(lines, "\n")
end

---@param timestamp integer?
---@return string
local function format_timestamp(timestamp)
	if type(timestamp) ~= "number" then
		return "-"
	end
	return tostring(os.date("%Y-%m-%d %H:%M:%S", timestamp))
end

---@param state string?
---@return string?
local function state_color(state)
	if state == "active" then
		return colorMap.success
	end
	if state == "failed" then
		return colorMap.error
	end
	if state == "starting" then
		return colorMap.info
	end
	if state == "stopping" or state == "to-be-started" then
		return colorMap.warn
	end
	return nil
end

---@param state string?
---@return { text: string, color: string? }
local function state_cell(state)
	return cell(state, state_color(state))
end

---@param health string?
---@return { text: string, color: string? }
local function health_cell(health)
	if health == "healthy" then
		return cell(health, colorMap.success)
	end
	if health == "unhealthy" then
		return cell(health, colorMap.error)
	end
	return cell(health)
end

---@param value boolean
---@return { text: string, color: string? }
local function ok_cell(value)
	return cell(value and "yes" or "no", value and colorMap.success or colorMap.error)
end

---@param status table<string, any>
---@return boolean
local function is_extended_list(status)
	for _, service_status in pairs(status) do
		return not table.is_array(service_status)
	end
	return false
end

---@param status table<string, any>
---@return string
local function format_tty_list(status)
	local rows = {}
	if is_extended_list(status) then
		for _, service_name in ipairs(sorted_keys(status)) do
			for _, module_name in ipairs(sorted_keys(status[service_name])) do
				local module_status = status[service_name][module_name]
				table.insert(rows, {
					service_name,
					module_name,
					state_cell(module_status.state),
					health_cell(module_status.health),
					cell(module_status.pid),
				})
			end
		end

		if #rows == 0 then
			return "No services"
		end

		return build_table({ "SERVICE", "MODULE", "STATE", "HEALTH", "PID" }, rows)
	end

	for _, service_name in ipairs(sorted_keys(status)) do
		local modules = {}
		for _, module_name in ipairs(status[service_name]) do
			table.insert(modules, module_name)
		end
		table.sort(modules)
		for _, module_name in ipairs(modules) do
			table.insert(rows, { service_name, module_name })
		end
	end

	if #rows == 0 then
		return "No services"
	end

	return build_table({ "SERVICE", "MODULE" }, rows)
end

---@param status table<string, any>
---@return string
local function format_tty_status(status)
	local rows = {}
	for _, service_name in ipairs(sorted_keys(status)) do
		local service_status = status[service_name]
		if service_status.ok and type(service_status.status) == "table" then
			for _, module_name in ipairs(sorted_keys(service_status.status)) do
				local module_status = service_status.status[module_name]
				table.insert(rows, {
					service_name,
					ok_cell(true),
					module_name,
					state_cell(module_status.state),
					health_cell(module_status.health),
					cell(module_status.exit_code),
					cell(format_timestamp(module_status.started)),
					cell(format_timestamp(module_status.stopped)),
					cell(nil),
				})
			end
		else
			table.insert(rows, {
				service_name,
				ok_cell(false),
				cell(nil),
				cell(nil),
				cell(nil),
				cell(nil),
				cell(nil),
				cell(nil),
				cell(service_status.error),
			})
		end
	end

	if #rows == 0 then
		return "No services"
	end

	return build_table({ "SERVICE", "OK", "MODULE", "STATE", "HEALTH", "EXIT", "STARTED", "STOPPED", "ERROR" }, rows)
end

---@param status table<string, any>
---@return string
local function format_tty_show(status)
	local lines = {}
	for index, service_name in ipairs(sorted_keys(status)) do
		if index > 1 then
			table.insert(lines, "")
		end
		table.insert(lines, service_name)
		for _, module_name in ipairs(sorted_keys(status[service_name])) do
			table.insert(lines, "  [" .. module_name .. "]")
			for line in hjson.encode(status[service_name][module_name]):gmatch("[^\n]+") do
				table.insert(lines, "    " .. line)
			end
		end
	end

	if #lines == 0 then
		return "No services"
	end

	return table.concat(lines, "\n")
end

---@param status table<string, AscendManagedServiceModuleStatus>
function format.status(status)
	if is_tty then
		return format_tty_status(status)
	end
	return hjson.encode_to_json(status, { indent = false })
end

---@param status table<string, any>
function format.list(status)
	if is_tty then
		return format_tty_list(status)
	end
	return hjson.encode_to_json(status, { indent = false })
end

---@param status table<string, any>
function format.show(status)
	if is_tty then
		return format_tty_show(status)
	end
	return hjson.encode_to_json(status, { indent = false })
end

function format.default(data)
	if is_tty then
		return hjson.encode(data)
	end
	return hjson.encode_to_json(data, { indent = false })
end

return format