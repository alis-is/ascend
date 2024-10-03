local workingDir = {}
workingDir.__index = workingDir

-- Constructor function to create a new DirHandler instance
function workingDir:new(path)
    local obj = setmetatable({}, self)
    obj.previousDir = os.cwd()  -- Save the current working directory
    obj.path = path
    os.chdir(path)  -- Change the working directory
    return obj
end

-- __close metamethod to restore the previous working directory
function workingDir:__close()
    os.chdir(self.previousDir)
end

return function(path)
    return workingDir:new(path)
end
