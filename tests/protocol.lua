local test = TEST or require "u-test"
local new_test_env = require "common.test-env"
local srcDir <close> = require "common.working-dir"("../src")
require "common.globals"
local jsonrpc = require "common.jsonrpc"
local encoding = require "common.encoding"

---@param env AscendTestEnv
---@param timeout number
---@return IPCSocket?, string?
local function connect_when_ready(env, timeout)
    local socketPath = path.combine(env:get_path(), "ascend.sock")
    local startTime = os.time()
    local lastError = "server did not become ready"

    while os.time() <= startTime + timeout do
        local socket, err = ipc.connect(socketPath)
        if socket then
            return socket, nil
        end
        lastError = err or lastError
        os.sleep(100, "ms")
    end

    return nil, lastError
end

---@param socket IPCSocket
---@param timeout number
---@return fun(): string?, string?
local function new_frame_reader(socket, timeout)
    local buffer = ""

    return function()
        while #buffer < 4 do
            local chunk, err = socket:read({ timeout = timeout })
            if not chunk then
                return nil, err
            end
            buffer = buffer .. chunk
        end

        local frameLength = encoding.decode_int(buffer:sub(1, 4))
        buffer = buffer:sub(5)

        while #buffer < frameLength do
            local chunk, err = socket:read({ timeout = timeout, buffer_size = frameLength - #buffer })
            if not chunk then
                return nil, err
            end
            buffer = buffer .. chunk
        end

        local payload = buffer:sub(1, frameLength)
        buffer = buffer:sub(frameLength + 1)
        return payload, nil
    end
end

---@param payload string
---@return string
local function frame_payload(payload)
    return encoding.encode_int(#payload, 4) .. payload
end

test["jsonrpc - encode request validates input without throwing"] = function()
    local ok, result, err = pcall(jsonrpc.encode_request, 123, "reload", {})
    if not ok then
        return false, tostring(result)
    end

    return result == nil and err == "id must be a string"
end

test["jsonrpc - fragmented request"] = function()
    local result, err = new_test_env({ services = {}, assets = {} }):run(function(env)
        local socket, connectErr = connect_when_ready(env, 5)
        if not socket then
            return false, connectErr
        end

        local request, requestErr = jsonrpc.encode_request("fragmented", "reload", {})
        if not request then
            return false, requestErr
        end

        local framed = frame_payload(request)
        socket:write(framed:sub(1, 2))
        socket:write(framed:sub(3, 6))
        socket:write(framed:sub(7))

        local read_frame = new_frame_reader(socket, 2000)
        local responsePayload, readErr = read_frame()
        if not responsePayload then
            return false, readErr
        end

        local response, parseErr = jsonrpc.parse_response(responsePayload)
        if not response then
            return false, parseErr
        end

        return response.id == "fragmented" and response.result == true
    end):result()

    test.assert(result, err)
end

test["jsonrpc - coalesced requests"] = function()
    local result, err = new_test_env({ services = {}, assets = {} }):run(function(env)
        local socket, connectErr = connect_when_ready(env, 5)
        if not socket then
            return false, connectErr
        end

        local firstRequest, firstErr = jsonrpc.encode_request("one", "reload", {})
        if not firstRequest then
            return false, firstErr
        end

        local secondRequest, secondErr = jsonrpc.encode_request("two", "reload", {})
        if not secondRequest then
            return false, secondErr
        end

        socket:write(frame_payload(firstRequest) .. frame_payload(secondRequest))

        local read_frame = new_frame_reader(socket, 2000)
        local firstResponsePayload, firstReadErr = read_frame()
        if not firstResponsePayload then
            return false, firstReadErr
        end
        local secondResponsePayload, secondReadErr = read_frame()
        if not secondResponsePayload then
            return false, secondReadErr
        end

        local firstResponse, firstParseErr = jsonrpc.parse_response(firstResponsePayload)
        if not firstResponse then
            return false, firstParseErr
        end

        local secondResponse, secondParseErr = jsonrpc.parse_response(secondResponsePayload)
        if not secondResponse then
            return false, secondParseErr
        end

        return firstResponse.id == "one" and firstResponse.result == true and
            secondResponse.id == "two" and secondResponse.result == true
    end):result()

    test.assert(result, err)
end

test["jsonrpc - malformed request does not poison connection"] = function()
    local result, err = new_test_env({ services = {}, assets = {} }):run(function(env)
        local socket, connectErr = connect_when_ready(env, 5)
        if not socket then
            return false, connectErr
        end

        socket:write(frame_payload("{"))

        local request, requestErr = jsonrpc.encode_request("after-error", "reload", {})
        if not request then
            return false, requestErr
        end
        socket:write(frame_payload(request))

        local read_frame = new_frame_reader(socket, 2000)
        local responsePayload, readErr = read_frame()
        if not responsePayload then
            return false, readErr
        end

        local response, parseErr = jsonrpc.parse_response(responsePayload)
        if not response then
            return false, parseErr
        end

        return response.id == "after-error" and response.result == true
    end):result()

    test.assert(result, err)
end

if not TEST then
    test.summary()
end