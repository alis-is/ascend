local log = {}

---@param path string
---@return integer?, string?
local function get_file_ino(path)
    local info, err = fs.file_info(path)
    if not info then
        return nil, err
    end
    if not info.ino then
        return nil, "file info does not contain ino"
    end
    return info.ino
end

---@param id string
---@param path string
local function open_log_file(id, path)
    local ino, stream, err
    local cache = ""

    return {
        read = function()
            if not stream then
                stream, err = require"eli.extensions.io".open_fstream(path, "r")
                if not stream then
                    return string.interpolate("${id} | failed to open file: ${error}", { id = id, error = err })
                end
            end
            local new_ino, err = get_file_ino(path)
            if not new_ino then
                log_warn("failed to get ino for file: ${path}", { path = path })
            elseif ino and ino ~= new_ino then
                -- read the rest of the file
                local rest = stream:read("a")
                -- split by lines
                local lines = rest:split("\n")
                for i = 1, #lines - 1 do
                    local line = lines[i]
                    if line then
                        lines[i] = string.interpolate("${id} | ${line}", { id = id, line = line })
                    end
                end
                stream:close()
                stream = nil
                ino = new_ino
                return string.join("\n", table.unpack(lines))
            end
            -- // TODO: optimize
            local content = stream:read("a", 0)
            if not content then
                return ""
            end
            content = cache .. content
            local content_without_new_line = content:match("^(.*)\n$")
            local lines
            if not content_without_new_line then
                lines = content:split("\n")
                cache = lines[#lines] or ""
                table.remove(lines, #lines)
            else
                lines = content_without_new_line:split("\n")
                cache = ""
            end

            for i = 1, #lines do
                lines[i] = string.interpolate("${id} | ${line}", { id = id, line = lines[i] })
            end

            return string.join("\n", table.unpack(lines))
        end,
    }
end

---@param files table<string, string>
function log.stream(files, timeout)
    local streams = {}
    for id, path in pairs(files) do
        table.insert(streams, open_log_file(id, path))
    end

    local start_time = os.time()
    while type(timeout) ~= "number" or timeout == 0 or start_time + timeout > os.time() do
        for i = 1, #streams do
            local line = streams[i].read()
            if line ~= "" then
                print(line)
            end
        end
        os.sleep(10, "ms")
    end
end

return log
