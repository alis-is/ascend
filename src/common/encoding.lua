local encoding = {}

function encoding.decode_int(bytes)
    local result = 0
    for i = #bytes, 1, -1 do
        result = result * 256 + string.byte(bytes, i)
    end
    return result
end

function encoding.encode_int(num, len)
	local bytes = {}
	for i = 1, len do
		bytes[i] = string.char(num % 256)
		num = math.floor(num / 256)
	end
	return table.concat(bytes)
end

return encoding