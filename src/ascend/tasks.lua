local is_stop_requested = require "ascend.signal"

local taskQueue = {}

local tasks = {}

--- add a task to the task queue
---@param task thread
function tasks.add(task)
	table.insert(taskQueue, task)
end

--- run all tasks in the task queue
---@param finalize boolean?
function tasks.run(finalize)
	while finalize or not is_stop_requested() do
		local newTaskQueue = {}
		for _, task in ipairs(taskQueue) do
			if coroutine.status(task) == "dead" then
				goto continue
			end
			coroutine.resume(task)
			table.insert(newTaskQueue, task)
			::continue::
		end

		taskQueue = newTaskQueue
		-- we want to exit only if we are finalizing and there are no more tasks
		-- we may keep running with no tasks if we assume that there will be more tasks/services added
		if finalize and #taskQueue == 0 then
			break
		end
		os.sleep(200, 1000)
	end
end

function tasks.clear()
	taskQueue = {}
end

return tasks
