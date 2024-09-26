local jsonrpc = require("common.jsonrpc")
local aenv = require("asctl.internals.env")
local args = require("common.args")
local encoding = require("common.encoding")
local aformat = require("asctl.format")

local client = {}
local counter = 0

---@param cmd string
---@param parameters any
---@returns any?, string?
function client.execute(cmd, parameters)
	local ok, socket = ipc.safe_connect(aenv.ipcEndpoint)
	if not ok then
		if type(socket) == "string" and socket:find("failed to connect", 1, true) and cmd == "stop" then
			log_warn("unable to connect to the server, it may be already stopped")
			os.exit(0)
		end
		return nil, string.interpolate("failed to connect to the server: ${error}", { error = socket })
	end
	counter = counter + 1
	local request, err = jsonrpc.encode_request(tostring(counter), cmd, parameters)
	if err then
		return nil, string.interpolate("failed to encode request: ${error}", { error = err })
	end

	local length = encoding.encode_int(#request, 4)

	socket:write(length .. request --[[@as string]])

	local time = os.time()
	local timeout = type(args.options.timeout) == "number" and args.options.timeout * 1000 or 120000

	while time + timeout > os.time() do
		local response, err = socket:read({ timeout = timeout })
		if not response then
			return nil, string.interpolate("failed to read response: ${error}", { error = err })
		end
		local decoded = encoding.decode_int(response:sub(1, 4))
		local response = response:sub(5)
		if #response < decoded then
			local restOfResponse = socket:read({ timeout = timeout, buffer_size = decoded - #response })
			if not restOfResponse then
				return nil, string.interpolate("failed to read response: ${error}", { error = err })
			end
			response = response .. restOfResponse
		end

		local response, err = jsonrpc.parse_response(response)
		if not response or err then
			return nil, string.interpolate("failed to parse response: ${error}", { error = err or "unknown" })
		end
		if response.id == tostring(counter) then
			if response.error then
				return nil, string.interpolate("failed to execute command: ${error}", { error = response.error.message })
			end

			return response.result
			-- if type(result) == "boolean" then
			-- 	os.exit(result and 0 or EXIT_COMMAND_ERROR)
			-- end

			-- if type(aformat[cmd]) == "function" then
			-- 	aformat[cmd](result.data)
			-- else
			-- 	aformat.default(result.data)
			-- end

			-- os.exit(result.success and 0 or EXIT_COMMAND_ERROR)
		else
			goto CONTINUE
		end
		::CONTINUE::
	end

	return nil, "timeout"
end

return client
