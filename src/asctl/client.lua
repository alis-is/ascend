local jsonrpc = require("common.jsonrpc")
local aenv = require("asctl.internals.env")
local args = require("common.args")
local encoding = require("common.encoding")
local is_tty = require "is_tty".is_stdout_tty()

local client = {}
local counter = 0

---@param cmd string
---@param parameters any
function client.execute(cmd, parameters)
	local socket, err = ipc.safe_connect(aenv.ipcEndpoint)
	if not socket then
		if type(err) == "string" and err:find("failed to connect", 1, true) and cmd == "stop" then
			log_warn("unable to connect to the server, it may be already stopped")
			os.exit(0)
		end
		log_error("failed to connect to the server: ${error}", { error = err })
		return
	end
	counter = counter + 1
	local request, err = jsonrpc.encode_request(tostring(counter), cmd, parameters)
	if err then
		log_error("failed to encode request: ${error}", { error = err })
		return
	end

	local length = encoding.encode_int(#request, 4)

	socket:write(length .. request --[[@as string]])

	local time = os.time()
	local timeout = type(args.options.timeout) == "number" and args.options.timeout * 1000 or 120000

	while time + timeout > os.time() do
		local response, err = socket:read({ timeout = timeout })
		if not response then
			log_error("failed to read response: ${error}", { error = err })
			return
		end
		local decoded = encoding.decode_int(response:sub(1, 4))
		local response = response:sub(5)
		if #response < decoded then
			local restOfResponse = socket:read({ timeout = timeout, buffer_size = decoded - #response })
			if not restOfResponse then
				log_error("failed to read response: ${error}", { error = err })
				return
			end
			response = response .. restOfResponse
		end

		local response, err = jsonrpc.parse_response(response)
		if not response or err then
			log_error("failed to parse response: ${error}", { error = err or "unknown" })
			return
		end
		if response.id == tostring(counter) then
			if response.error then
				log_error("failed to execute command: ${error}", { error = response.error.message })
				os.exit(EXIT_JSONRPC_ERROR)
			end
			local result = response.result
			if type(result) == "boolean" then
				os.exit(result and 0 or EXIT_COMMAND_ERROR)
			end
			if is_tty then
				print(hjson.encode(result.data))
			else
				print(hjson.encode_to_json(result.data, { indent = false }))
			end
			os.exit(result.success and 0 or EXIT_COMMAND_ERROR)
		else
			goto CONTINUE
		end
		::CONTINUE::
	end

	log_error("timeout")
end

return client
