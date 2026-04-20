local jsonrpc = require("common.jsonrpc")
local aenv = require("asctl.internals.env")
local args = require("common.args")
local encoding = require("common.encoding")

local client = {}
local counter = 0

local DEFAULT_TIMEOUT_SECONDS = 120
local FRAME_HEADER_LENGTH = 4

---@param socket IPCSocket
---@param timeout_ms integer
---@return string?, string?
local function read_framed_response(socket, timeout_ms)
	local header = ""
	while #header < FRAME_HEADER_LENGTH do
		local chunk, err = socket:read({
			timeout = timeout_ms,
			buffer_size = FRAME_HEADER_LENGTH - #header,
		})
		if not chunk then
			return nil, err
		end
		header = header .. chunk
	end

	local response_length = encoding.decode_int(header)
	if response_length <= 0 then
		return nil, "invalid response length"
	end

	local payload = ""
	while #payload < response_length do
		local chunk, err = socket:read({
			timeout = timeout_ms,
			buffer_size = response_length - #payload,
		})
		if not chunk then
			return nil, err
		end
		payload = payload .. chunk
	end

	return payload
end

---@param cmd string
---@param parameters any
---@returns any?, string?
function client.execute(cmd, parameters)
	local socket, err = ipc.connect(aenv.ipcEndpoint) --[[@as IPCSocket]]
	if not socket then
		if cmd == "stop" and type(err) == "string" and err:find("failed to connect", 1, true) then
			log_warn("unable to connect to the server, it may be already stopped")
			os.exit(0)
		end
		return nil, string.interpolate("failed to connect to the server: ${error}", { error = err })
	end
	counter = counter + 1
	local request, err = jsonrpc.encode_request(tostring(counter), cmd, parameters)
	if err then
		return nil, string.interpolate("failed to encode request: ${error}", { error = err })
	end

	local length = encoding.encode_int(#request, 4)

	socket:write(length .. request --[[@as string]])

	local timeout_seconds = type(args.options.timeout) == "number" and args.options.timeout or DEFAULT_TIMEOUT_SECONDS
	local timeout_ms = math.max(0, math.ceil(timeout_seconds * 1000))
	local response_payload, read_err = read_framed_response(socket, timeout_ms)
	if not response_payload then
		return nil, string.interpolate("failed to read response: ${error}", { error = read_err })
	end

	local response, parse_err = jsonrpc.parse_response(response_payload)
	if not response or parse_err then
		return nil, string.interpolate("failed to parse response: ${error}", { error = parse_err or "unknown" })
	end

	if response.id ~= tostring(counter) then
		return nil, string.interpolate("received response for unexpected request id: ${id}", {
			id = tostring(response.id),
		})
	end

	if response.error then
		return nil, string.interpolate("failed to execute command: ${error}", { error = response.error.message })
	end

	return response.result
end

return client
