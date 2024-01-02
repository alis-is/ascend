local jsonrpc = {}

---@class JsonRpcRequest
---@field jsonrpc "2.0"
---@field id string
---@field method string
---@field params any

---@class JsonRpcError
---@field code number
---@field message string
---@field data any

---@class JsonRpcResponse
---@field jsonrpc "2.0"
---@field id string
---@field result any?
---@field error JsonRpcError?

---@class JsonRpcNotification
---@field jsonrpc "2.0"
---@field method string
---@field params any

---Parse a jsonrpc request
---@param msg string
---@return JsonRpcRequest?, string?
function jsonrpc.parse_request(msg)
	local ok, result = hjson.safe_parse(msg)
	if not ok then
		return nil, string.join_strings(" - ", "failed to decode request", result)
	end
	if type(result) ~= "table" then
		return nil, "request must be an object"
	end
	if result.jsonrpc ~= "2.0" then
		return nil, "unsupported jsonrpc version"
	end
	if type(result.id) ~= "string" then
		return nil, "id must be a string"
	end
	if type(result.method) ~= "string" then
		return nil, "method must be a string"
	end
	return result
end

---Parse a jsonrpc response 
---@param msg string
---@return JsonRpcResponse?, string?
function jsonrpc.parse_response(msg)
	local ok, result = hjson.safe_parse(msg)
	if not ok then
		return nil, string.join_strings(" - ", "failed to decode response", result)
	end
	if type(result) ~= "table" then
		return nil, "response must be an object"
	end
	if result.jsonrpc ~= "2.0" then
		return nil, "unsupported jsonrpc version"
	end
	if type(result.id) ~= "string" then
		return nil, "id must be a string"
	end
	if result.result ~= nil and result.error ~= nil then
		return nil, "response cannot contain both result and error"
	end
	if result.result == nil and result.error == nil then
		return nil, "response must contain either result or error"
	end
	if result.error ~= nil then
		if type(result.error) ~= "table" then
			return nil, "error must be an object"
		end
		if type(result.error.code) ~= "number" then
			return nil, "error code must be a number"
		end
		if type(result.error.message) ~= "string" then
			return nil, "error message must be a string"
		end
	end
	return result
end

---Parse a jsonrpc notification
---@param msg string
---@return JsonRpcNotification?, string?
function jsonrpc.parse_notification(msg)
	local ok, result = hjson.safe_parse(msg)
	if not ok then
		return nil, string.join_strings(" - ", "failed to decode notification", result)
	end
	if type(result) ~= "table" then
		return nil, "notification must be an object"
	end
	if result.jsonrpc ~= "2.0" then
		return nil, "unsupported jsonrpc version"
	end
	if type(result.method) ~= "string" then
		return nil, "method must be a string"
	end
	return result
end

---Encode a jsonrpc request
---@param id string
---@param method string
---@param params any
---@return string?, string?
function jsonrpc.encode_request(id, method, params)
	if type(id) ~= "string" and #id > 0 then
		return nil, "id must be a string"
	end

	if type(method) ~= "string" and #method > 0 then
		return nil, "method must be a string"
	end

	return hjson.encode({
		jsonrpc = "2.0",
		id = id,
		method = method,
		params = params,
	})
end

---Encode a jsonrpc response
---@param id string
---@param result any?
---@param error JsonRpcError?
---@return string?, string?
function jsonrpc.encode_response(id, result, error)
	if type(id) ~= "string" and #id > 0 then
		return nil, "id must be a string"
	end

	if result ~= nil and error ~= nil then
		return nil, "response cannot contain both result and error"
	end

	if result == nil and error == nil then
		return nil, "response must contain either result or error"
	end

	return hjson.encode({
		jsonrpc = "2.0",
		id = id,
		result = result,
		error = error,
	})
end

---Encode a jsonrpc notification
---@param method string
---@param params any
---@return string?, string?
function jsonrpc.encode_notification(method, params)
	if type(method) ~= "string" and #method > 0 then
		return nil, "method must be a string"
	end

	return hjson.encode({
		jsonrpc = "2.0",
		method = method,
		params = params,
	})
end

jsonrpc.error_codes = {
	PARSE_ERROR = -32700,
	INVALID_REQUEST = -32600,
	METHOD_NOT_FOUND = -32601,
	INVALID_PARAMS = -32602,
	INTERNAL_ERROR = -32603,
}

return jsonrpc
