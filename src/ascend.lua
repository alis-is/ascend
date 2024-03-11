#!/usr/sbin/eli

require "common.globals"
require "common.log" ("ascend")

local args = require "common.args"

if args.command == "version" or args.options["version"] then
	print(string.interpolate("ascend ${version}", { version = require "version-info".VERSION }))
	os.exit(0)
end

GLOBAL_LOGGER.options.level = args.options["log-level"] or "info"

require "ascend.bootstrap" ()
local services = require "ascend.services"
local server = require "ascend.server"
local tasks = require "ascend.tasks"

local ok, err = services.init()
if not ok then
	log_error("failed to initialize services: ${error}", { error = err })
	os.exit(EXIT_FAILED_TO_LOAD_SERVICES)
end

tasks.add(services.manage(true))
tasks.add(server.listen())

log_info("ascend started")
tasks.run()

tasks.clear()
tasks.add(services.stop_all())
tasks.run(true)

log_info("ascend stopped")
