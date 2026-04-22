local args = require "common.args"
local slices = require "common.slices"

local defaults = slices.resolve_asctl_defaults({
	user_option = args.options.user,
})

return util.merge_tables({
	ipcEndpoint = args.options.socket or
		env.get_env("ASCEND_SOCKET"),
}, defaults)
