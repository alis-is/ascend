local args = require "common.args"

return {
	ipcEndpoint = args.options.socket or
		env.get_env("ASCEND_SOCKET") or
		"/tmp/ascend.sock",
}
