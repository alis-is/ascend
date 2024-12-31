#!/usr/bin/env eli

require "common.globals"
require "common.log" ("ascend")
local input = require "common.input"

local args = require "common.args"

if args.command == "version" or args.options["version"] then
	print(string.interpolate("ascend ${version}", { version = require "version-info".VERSION }))
	os.exit(0)
end

GLOBAL_LOGGER.options.level = args.options["log-level"] or "info"
local timeout = input.parse_time_value(args.options["timeout"])
if not timeout and args.options["timeout"] then
	log_warn("Invalid timeout value: ${value}", { value = args.options["timeout"] })
end


local init = require "ascend.init"
local services = require "ascend.services"
local server = require "ascend.server"
local tasks = require "ascend.tasks"

init.run() -- initialize ascend and services
if args.command == "init-only" or args.options["init-only"] then
	os.exit(0)
end

tasks.add(services.manage(true))
tasks.add(server.listen())
tasks.add(services.healthcheck())

local end_time = timeout and os.time() + timeout or nil
log_info("ascend started")
local stop_reason = tasks.run({ stop_on_error = true , end_time = end_time })

tasks.clear()
tasks.add(services.stop_all())
tasks.run({ ignore_stop = true, stop_on_empty = true })

log_info("ascend stopped")

if stop_reason == "error" then
	os.exit(1)
end

if stop_reason == "timeout" then
	os.exit(2)
end
