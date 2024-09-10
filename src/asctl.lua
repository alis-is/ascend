#!/usr/bin/env eli

require "common.globals"
require "common.log" ("asctl")

local args = require "common.args"

if args.command == "version" or args.options["version"] then
	print(string.interpolate("asctl ${version}", { version = require "version-info".VERSION }))
	os.exit(0)
end

local client = require "asctl.client"

GLOBAL_LOGGER.options.level = args.options["log-level"] or "info"

client.execute(args.command, args.parameters)

