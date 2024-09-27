#!/usr/bin/env eli

local signal = require "os.signal"

local function handle_sigterm()
    print("Received SIGTERM, but ignoring it.")
end

signal.handle(signal.SIGTERM, handle_sigterm)

print("Script is running, try sending SIGTERM (kill -15 <PID>)")

while true do
    os.sleep(5)
end
