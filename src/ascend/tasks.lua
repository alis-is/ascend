local is_stop_requested = require "ascend.signal"

---@class TaskPoolOptions
---@field stopOnEmpty boolean?
---@field stopOnError boolean?
---@field ignoreStop boolean?
---@field end_time number?

local taskQueue = {}

local function timed_out(end_time)
	if not end_time then
		return false
	end
	local result = os.time() >= end_time
	if result then
		log_info("!!! timed out !!!")
	end
	return result
end

local tasks = {}

--- add a task to the task queue
---@param task thread
function tasks.add(task)
	table.insert(taskQueue, task)
end

--- run all tasks in the task queue
---@param options TaskPoolOptions
function tasks.run(options)
	if not options then
		options = {}
	end

	while options.ignoreStop or not is_stop_requested() and not timed_out(options.end_time) do
		local stop = false

		local newTaskQueue = {}
		for _, task in ipairs(taskQueue) do
			if coroutine.status(task) == "dead" then
				goto continue
			end
			local ok, err = coroutine.resume(task)
			if not ok then
				log_error("!!! task failed !!!", { error = err })
				if options.stopOnError then
					stop = true
					break
				end
			end
			table.insert(newTaskQueue, task)
			::continue::
		end

		taskQueue = newTaskQueue
		if stop or (options.stopOnEmpty and #taskQueue == 0) then
			break
		end
		os.sleep(100, 1000)
	end
end

function tasks.clear()
	taskQueue = {}
end

return tasks
