#!/usr/bin/env eli

local ascend_init_value = os.getenv("ASCEND_INIT")

if ascend_init_value then
	print("ASCEND_INIT: " .. ascend_init_value)
else
	print("ASCEND_INIT is not set.")
end

while true do
	print("date:", os.date())
	os.sleep(5)
end
