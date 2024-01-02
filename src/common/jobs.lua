local jobs = {}

--- create a queue of jobs
---@param params any[][]
---@param jobFn fun(...)
function jobs.create_queue(params, jobFn)
	local queue = {}
	for _, param in ipairs(params) do
		table.insert(queue, coroutine.create(function()
			jobFn(table.unpack(param))
		end))
	end
	return queue
end

--- run all jobs in the queue
---@param jobs thread[]
function jobs.run_queue(jobs)
	local _, isMainThread = coroutine.running()

	while #jobs > 0 do
		local newJobs = {}
		for _, job in ipairs(jobs) do
			if coroutine.status(job) ~= "dead" then
				table.insert(newJobs, job)
				coroutine.resume(job)
			end
		end
		jobs = newJobs
		if not isMainThread then
			coroutine.yield()
		end
	end
end

---Converts an array of values to an array of params
---@param array any[]
---@return any[][]
function jobs.array_to_array_of_params(array)
	local params = {}
	for _, item in ipairs(array) do
		table.insert(params, { item })
	end
	return params
end

return jobs
