local args = require "common.args"

return {
	ipcEndpoint = args.options.socket or
		os.getenv("ASCEND_SOCKET") or
		"/tmp/ascend.sock",
}
