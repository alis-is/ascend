local jsonrpc = require("common.jsonrpc")
local encoding = require("common.encoding")
local jobs = require("common.jobs")
local is_stop_requested = require("ascend.signal")
local aenv = require "ascend.internals.env"
local services = require "ascend.services"
local tasks = require "ascend.tasks"

local server = {}

---@class ClientMessageBuffer
---@field msgLen number
---@field msg string

---@type table<IPCSocket, ClientMessageBuffer>
local clients = {}

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
	for _, name in ipairs(params) do
		if not services.is_managed(name) then
			return false, "service is not found"
		end
	end
	return true
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
			local responseData = {}
			local success = true
			---@type thread[]
			local stopJobs = jobs.create_queue(jobs.array_to_array_of_params(request.params), function(name)
				local ok, err = services.stop(name, true)
				success = success and ok
				responseData[name] = {
					ok = ok,
					error = err
				}
			end)
			jobs.run_queue(stopJobs)
			respond({ success = success, data = responseData })
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
			local responseData = {}
			local success = true
			---@type thread[]
			local startJobs = jobs.create_queue(jobs.array_to_array_of_params(request.params), function(name)
				local ok, err = services.start(name)
				success = success and ok
				responseData[name] = {
					ok = ok,
					error = err
				}
			end)
			jobs.run_queue(startJobs)
			respond({ success = success, data = responseData })
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
			local responseData = {}
			local success = true
			---@type thread[]
			local restartJobs = jobs.create_queue(jobs.array_to_array_of_params(request.params), function(name)
				local ok, err = services.restart(name)
				success = success and ok
				responseData[name] = {
					ok = ok,
					error = err
				}
			end)
			jobs.run_queue(restartJobs)
			respond({ success = success, data = responseData })
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
	status = function(request, respond)
		if not check_params(request.params, check_is_array_of_strings, respond) then
			return
		end

		if not check_params(request.params, check_manages_just_managed_services, respond) then
			return
		end

		tasks.add(coroutine.create(function()
			local responseData = {}
			local success = true
			---@type thread[]
			local statusJobs = jobs.create_queue(jobs.array_to_array_of_params(request.params), function(name)
				local status, err = services.status(name)
				success = success and status ~= nil
				if not status then
					responseData[name] = {
						ok = false,
						error = err
					}
					return
				else
					responseData[name] = {
						ok = true,
						status = status
					}
				end
			end)
			jobs.run_queue(statusJobs)
			respond({ success = success, data = responseData })
		end))
	end,
	logs = function(request, respond)
		-- // TODO: implement
		respond(nil, {
			code = jsonrpc.error_codes.INTERNAL_ERROR,
			message = "not implemented"
		})
	end,
	list = function(_, respond)
		respond({
			success = true,
			data = services.list()
		})
	end,
}

function server.listen()
	return coroutine.create(function()
		local server, err = ipc.listen(aenv.ipcEndpoint, {
			accept = function(socket)
				clients[socket] = { msgLen = 0, msg = "" }
			end,
			data = function(socket, msg)
				local incomingLen = #msg
				if incomingLen == 0 then return end
				local clientBuffer = clients[socket]
				if clientBuffer.msgLen == 0 then
					-- take first 4 bytes as length
					local len = encoding.decode_int(msg:sub(1, 4))
					clientBuffer.msgLen = len
					clientBuffer.msg = msg:sub(5)
				end

				if clientBuffer.msgLen > 0 and clientBuffer.msgLen == #clientBuffer.msg then
					local request, err = jsonrpc.parse_request(clientBuffer.msg)
					clientBuffer.msgLen = 0
					clientBuffer.msg = ""
					if err or request == nil then
						log_warn("failed to parse request: ${error}", { error = err or "unknown" })
						return
					end
					if type(request.id) ~= "string" then
						log_debug("received notification: ${method}", { method = request.method })
						return
					end
					local handler = methodHandlers[request.method]
					if not handler then
						local response, err = jsonrpc.encode_response(request.id, nil, {
							code = jsonrpc.error_codes.METHOD_NOT_FOUND,
							message = "method not found"
						})
						if err then
							log_warn("failed to encode response: ${error}", { error = err })
							return
						end
						socket:write(response --[[@as string]])
						return
					end
					log_trace("received request id - ${id}: ${method}", { id = request.id, method = request.method })
					handler(request, function(result, error)
						local response, err = jsonrpc.encode_response(request.id, result, error)
						if err then
							log_warn("failed to encode response: ${error}", { error = err })
							return
						end
						local responseLen = #response
						local responseLenBytes = encoding.encode_int(responseLen, 4)
						socket:write(responseLenBytes .. response)
					end)
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
