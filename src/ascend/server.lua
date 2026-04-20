local jsonrpc = require("common.jsonrpc")
local encoding = require("common.encoding")
local jobs = require("common.jobs")
local is_stop_requested = require("ascend.signal")
local aenv = require "ascend.internals.env"
local services = require "ascend.services"
local tasks = require "ascend.tasks"

local server = {}

local FRAME_HEADER_LENGTH = 4

---@class ClientMessageBuffer
---@field msg_length number
---@field msg string

---@type table<IPCSocket, ClientMessageBuffer>
local clients = {}

---@param socket IPCSocket
---@param response string
local function write_framed_response(socket, response)
	local responseLen = #response
	local responseLenBytes = encoding.encode_int(responseLen, FRAME_HEADER_LENGTH)
	socket:write(responseLenBytes .. response)
end

---@param clientBuffer ClientMessageBuffer
---@return string?
local function take_next_message(clientBuffer)
	if clientBuffer.msg_length == 0 then
		if #clientBuffer.msg < FRAME_HEADER_LENGTH then
			return nil
		end

		clientBuffer.msg_length = encoding.decode_int(clientBuffer.msg:sub(1, FRAME_HEADER_LENGTH))
		clientBuffer.msg = clientBuffer.msg:sub(FRAME_HEADER_LENGTH + 1)
	end

	if clientBuffer.msg_length <= 0 then
		clientBuffer.msg_length = 0
		clientBuffer.msg = ""
		return ""
	end

	if #clientBuffer.msg < clientBuffer.msg_length then
		return nil
	end

	local message = clientBuffer.msg:sub(1, clientBuffer.msg_length)
	clientBuffer.msg = clientBuffer.msg:sub(clientBuffer.msg_length + 1)
	clientBuffer.msg_length = 0
	return message
end

---@class ServerHandlers
---@field new_task fun(task: thread)

---@param params any
---@param check fun(params: any): boolean, string?
---@param respond fun(response: any, err: JsonRpcError)
local function check_params(params, check, respond)
	local ok, err = check(params)
	if not ok then
		respond(nil, {
			code = jsonrpc.error_codes.INVALID_PARAMS,
			message = "invalid params",
			data = {
				params = params
			}
		})
		return false, err
	end
	return true
end

local function check_is_array_of_strings(params)
	if not table.is_array(params) then
		return false, "params must be an array"
	end
	for _, name in ipairs(params) do
		if type(name) ~= "string" then
			return false, "params must be an array of strings"
		end
	end
	return true
end

local function check_manages_just_managed_services(params)
	if not table.is_array(params) then
		params = { params }
	end
	for _, name in ipairs(params) do
		if not services.is_managed(name) then
			return false, "service is not found"
		end
	end

	return true
end

local function alter_params(params)
	local options = params.options
	params.options = nil
	for k, v in pairs(params) do
		params[tonumber(k)] = v
		params[k] = nil
	end

	return params, options
end

---@type table<string, fun(request: JsonRpcRequest, respond: fun(response: any, err: JsonRpcError?))>
local methodHandlers = {
	stop = function(request, respond)
		if not check_params(request.params, check_is_array_of_strings, respond) then
			return
		end

		if not check_params(request.params, check_manages_just_managed_services, respond) then
			return
		end
		tasks.add(coroutine.create(function()
			local response_data = {}
			local success = true
			---@type thread[]
			local stopJobs = jobs.create_queue(jobs.array_to_array_of_params(request.params), function(name)
				local ok, err = services.stop(name, true)
				success = success and ok
				response_data[name] = {
					ok = ok,
					error = err
				}
			end)
			jobs.run_queue(stopJobs)
			respond({ success = success, data = response_data })
		end))
	end,
	start = function(request, respond)
		if not check_params(request.params, check_is_array_of_strings, respond) then
			return
		end

		if not check_params(request.params, check_manages_just_managed_services, respond) then
			return
		end

		tasks.add(coroutine.create(function()
			local response_data = {}
			local success = true
			---@type thread[]
			local startJobs = jobs.create_queue(jobs.array_to_array_of_params(request.params), function(name)
				local ok, err = services.start(name, { manual = true })
				success = success and ok
				response_data[name] = {
					ok = ok,
					error = err
				}
			end)
			jobs.run_queue(startJobs)
			respond({ success = success, data = response_data })
		end))
	end,
	restart = function(request, respond)
		if not check_params(request.params, check_is_array_of_strings, respond) then
			return
		end

		if not check_params(request.params, check_manages_just_managed_services, respond) then
			return
		end

		tasks.add(coroutine.create(function()
			local response_data = {}
			local success = true
			---@type thread[]
			local restartJobs = jobs.create_queue(jobs.array_to_array_of_params(request.params), function(name)
				local ok, err = services.restart(name, { manual = true })
				success = success and ok
				response_data[name] = {
					ok = ok,
					error = err
				}
			end)
			jobs.run_queue(restartJobs)
			respond({ success = success, data = response_data })
		end))
	end,
	reload = function(request, respond)
		local ok, err = services.reload()
		if not ok then
			respond(nil, {
				code = jsonrpc.error_codes.INTERNAL_ERROR,
				message = err or "unknown error"
			})
			return
		end
		respond(true)
	end,
	["ascend-health"] = function(request, respond)
		local strict = table.includes(request.params, "strict")
		respond({ success = true, data = services.get_ascend_health(strict) })
	end,
	status = function(request, respond)
		if not check_params(request.params, check_is_array_of_strings, respond) then
			return
		end

		if not check_params(request.params, check_manages_just_managed_services, respond) then
			return
		end

		tasks.add(coroutine.create(function()
			local response_data = {}
			local success = true
			---@type thread[]
			local statusJobs = jobs.create_queue(jobs.array_to_array_of_params(request.params), function(name)
				local status, err = services.status(name)
				success = success and status ~= nil
				if not status then
					response_data[name] = {
						ok = false,
						error = err
					}
					return
				else
					response_data[name] = {
						ok = true,
						status = status
					}
				end
			end)
			jobs.run_queue(statusJobs)
			respond({ success = success, data = response_data })
		end))
	end,
	logs = function(request, respond)
		if not check_params(request.params, check_is_array_of_strings, respond) then
			return
		end

		if not check_params(request.params, check_manages_just_managed_services, respond) then
			return
		end

		local result = {}
		for _, name in ipairs(request.params) do
			local serviceName, logFilesOrError = services.logs(name)
			if not serviceName then
				result[name] = logFilesOrError
			else
				result[serviceName] = logFilesOrError
			end
		end
		respond({ success = true, data = result })
	end,
	list = function(request, respond)
		local params, options = alter_params(request.params or {})

		if #params > 1 and not check_params(request.params, check_is_array_of_strings, respond) then
			return
		end

		if #params > 1 and not check_params(request.params, check_manages_just_managed_services, respond) then
			return
		end

		respond({
			success = true,
			data = services.list(params, options.extended)
		})
	end,
	show = function(request, respond)
		local params = request.params

		if #params > 1 and not check_params(request.params, check_is_array_of_strings, respond) then
			return
		end

		if #params > 1 and not check_params(request.params, check_manages_just_managed_services, respond) then
			return
		end

		local result, err = services.show(params)
		if not result then
			respond(nil, {
				code = jsonrpc.error_codes.INTERNAL_ERROR,
				message = err or "unknown error"
			})
			return
		end

		respond({
			success = true,
			data = result
		})
	end,
}

function server.listen()
	return coroutine.create(function()
		local server, err = ipc.listen(aenv.ipcEndpoint, {
			accept = function(socket)
				clients[socket] = { msg_length = 0, msg = "" }
			end,
			data = function(socket, msg)
				local incomingLen = #msg
				if incomingLen == 0 then return end
				local clientBuffer = clients[socket]
				clientBuffer.msg = clientBuffer.msg .. msg

				while true do
					local requestMessage = take_next_message(clientBuffer)
					if requestMessage == nil then
						return
					end
					if requestMessage == "" then
						log_warn("failed to parse request: invalid message length")
						return
					end

					local request, err = jsonrpc.parse_request(requestMessage)
					if err or request == nil then
						log_warn("failed to parse request: ${error}", { error = err or "unknown" })
						goto CONTINUE
					end
					if type(request.id) ~= "string" then
						log_debug("received notification: ${method}", { method = request.method })
						goto CONTINUE
					end
					local handler = methodHandlers[request.method]
					if not handler then
						local response, responseErr = jsonrpc.encode_response(request.id, nil, {
							code = jsonrpc.error_codes.METHOD_NOT_FOUND,
							message = "method not found"
						})
						if responseErr then
							log_warn("failed to encode response: ${error}", { error = responseErr })
							goto CONTINUE
						end
						write_framed_response(socket, response --[[@as string]])
						goto CONTINUE
					end
					log_trace("received request id - ${id}: ${method}", { id = request.id, method = request.method })
					local success, handlerErr = pcall(handler, request, function(result, error)
						local response, responseErr = jsonrpc.encode_response(request.id, result, error)
						if responseErr then
							log_warn("failed to encode response: ${error}", { error = responseErr })
							return
						end
						write_framed_response(socket, response --[[@as string]])
					end)
					if not success then
						log_error("failed to handle request: ${error}", { error = handlerErr })
						local response, responseErr = jsonrpc.encode_response(request.id, nil, {
							code = jsonrpc.error_codes.INTERNAL_ERROR,
							message = "internal error"
						})
						if responseErr then
							log_warn("failed to encode response: ${error}", { error = responseErr })
							goto CONTINUE
						end
						write_framed_response(socket, response --[[@as string]])
					end
					::CONTINUE::
				end
			end,
			disconnected = function(socket)
				clients[socket] = nil
			end,
		}, {
			timeout = 250,
			is_stop_requested = is_stop_requested
		})
		coroutine.yield(server, err)
	end)
end

return server
