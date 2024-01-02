local signal = require "os.signal"

local stopRequested = false
local function signalHandler()
	log_debug("received signal")
	stopRequested = true
	signal.reset(signal.SIGINT)
	signal.reset(signal.SIGTERM)
end
signal.handle(signal.SIGTERM, signalHandler)
signal.handle(signal.SIGINT, signalHandler)

return function ()
	return stopRequested
end