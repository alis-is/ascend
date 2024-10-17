local input = {}

function input.parse_size_value(val)
    if tonumber(val) then
        return tonumber(val)
    end

    local suffix = val:sub(-1):lower()
    local num = tonumber(val:sub(1, -2))

    if suffix == "k" then
        return num * 1024
    elseif suffix == "m" then
        return num * 1024 * 1024
    elseif suffix == "g" then
        return num * 1024 * 1024 * 1024
    end

    return nil, "Invalid file size value"
end

function input.parse_time_value(val)
    if type(val) ~= "string" and type(val) ~= "number" then
        return nil, "Invalid time value"
    end
    if tonumber(val) then
        return tonumber(val)
    end

    local suffix = val:sub(-1):lower()
    local num = tonumber(val:sub(1, -2))

    if suffix == "s" then
        return num
    elseif suffix == "m" then
        return num * 60
    elseif suffix == "h" then
        return num * 60 * 60
    end

    return nil, "Invalid time value"
end

return input