local aenv = require "ascend.internals.env"

-- // TODO: implement maximum buffer size
local BUFFER_SIZE = tonumber(os.getenv("ASCEND_LOG_BUFFER_SIZE")) or 1024 * 1024 * 1 -- 1MB

local log = {}

-- Helper to get file size
local function get_file_size(file)
    local current = file:seek()
    local size = file:seek("end")
    file:seek("set", current)
    return size
end

local function create_log_directory(log_file)
    local log_dir = path.dir(log_file)
    if not fs.exists(log_dir) then
        fs.mkdirp(log_dir)
    end
end

local function normalize_log_file_path(log_file)
    if path.isabs(log_file) then
        return log_file
    end

    return path.combine(aenv.logDirectory, log_file)
end
---@class AscendRotatingLogFile
---@field private filename string
---@field private max_file_size number
---@field private max_file_count number
---@field private current_file file*?
---@field private current_size number
---@field write fun(self: AscendRotatingLogFile, message: string)
---@field close fun(self: AscendRotatingLogFile)
---@field get_filename fun(self: AscendRotatingLogFile): string

---@param module_definition AscendServiceModuleDefinition
---@return AscendRotatingLogFile
function log.create_log_file(module_definition)
    local log_file = {}
    log_file.filename = normalize_log_file_path(module_definition.log_file)
    log_file.max_file_size = module_definition.log_max_size
    log_file.max_file_count = module_definition.log_max_files
    log_file.is_rotating = module_definition.log_rotate

    create_log_directory(log_file.filename)
    log_file.current_file = io.open(log_file.filename, "a+b")
    log_file.current_size = get_file_size(log_file.current_file)

    -- Helper to rotate log files
    local function rotate_logs()
        if not log_file.is_rotating or log_file.max_file_count <= 1 then
            return
        end

        -- Close the current log file if open
        if log_file.current_file then
            log_file.current_file:close()
        end

        -- Shift older logs
        for i = log_file.max_file_count - 2, 1, -1 do
            local old_file = log_file.filename .. "." .. i
            local new_file = log_file.filename .. "." .. (i + 1)
            os.rename(old_file, new_file) -- Renames files to the next index
        end

        -- Rename the current log to .1
        os.rename(log_file.filename, log_file.filename .. ".1")

        -- Open a new log file
        log_file.current_file = io.open(log_file.filename, "w+b")
        log_file.current_size = 0
    end

    -- Function to write to the log file
    function log_file:write(message)
        if type(message) ~= "string" then
            return
        end
        -- If max_file_count is 0, do not write to file
        if self.max_file_count == 0 then
            return
        end

        if self.current_file == nil then
            self.current_file = io.open(self.filename, "a+b")
            self.current_size = get_file_size(self.current_file)
        end

        -- Check if the current file size exceeds the max allowed size
        local needs_rotate = self.current_size + #message >= self.max_file_size and self.max_file_count > 1

        -- Write the message to the file
        self.current_file:write(message)
        self.current_file:flush() -- Ensure data is written to disk immediately

        -- Update the current file size
        self.current_size = self.current_size + #message

        -- If the file needs to be rotated, do so
        if needs_rotate then
            rotate_logs()
        end
    end

    function log_file:get_filename()
        return self.filename
    end

    -- Function to close the log file
    function log_file:close()
        if self.current_file then
            self.current_file:close()
            self.current_file = nil
        end
    end

    -- Expose the log object with metatable for method access
    setmetatable(log_file, {
        __index = function(_, key)
            return log_file[key]
        end
    })

    return log_file
end

---@param module AscendManagedServiceModule
function log.collect_output(module)
    if module.__output == nil then
        return
    end

    if module.__output_file == nil then
        return nil
    end
    module.__output_file:write(module.__output:read("a", 0)) -- Write the output to the log file
end

return log
