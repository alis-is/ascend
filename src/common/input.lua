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

return input