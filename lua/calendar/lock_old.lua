local M = {}
local lockDir = ""
local isPrimary = false
local lockIndex = 0
local dataPath = vim.fn.stdpath("data")
local timeFmt = "%Y %b %d %X"
if type(dataPath) == "table" then
    lockDir = dataPath[1]
else
    lockDir = dataPath
end

---@type CalendarLockOptions
local opts = {
    lockDir = lockDir,
}

---@param options CalendarLockOptions
function M.setup(options)
    for key, _ in pairs(opts) do
        if options[key] ~= nil then
            opts[key] = options[key]
        end
    end
    M.createLock()
end

---@param index number?
---@return string
function M.getLockFileName(index)
    index = index or lockIndex
    if index == 0 then
        print("No index found")
        return ""
    end
    return opts.lockDir .. "/calendar_" .. index .. ".lock"
end

function M.checkPrimaryLockExists()
    local file = io.open(M.getLockFileName(1), "r")
    if file == nil then
        return false
    end
    file:close()
    return not M.isStale(1)
end

function M.lockCountBelow()
    local count = 0
    for i = 1, lockIndex do
        if i == lockIndex then
            break
        end
        if M.lockFileExists(i) then
            count = count + 1
        end
    end
    return count
end

function M.removeCurrentLock()
    local fileName = M.getLockFileName(lockIndex)
    os.remove(fileName)
end

function M.updateLock()
    if lockIndex == 0 then
        print("lock does not exist")
        return
    end
    local fname = M.getLockFileName()
    local file = io.open(fname, "w")
    if file == nil then
        error("could not open lock file")
    end
    file:write(vim.fn.strftime(timeFmt))
    file:close()
end

function M.createLock()
    local index = 1
    while M.lockFileExists(index) do
        index = index + 1
    end
    lockIndex = index
    isPrimary = index == 1
end

function M.isStale(index)
    local file = io.open(M.getLockFileName(index), "r")
    if index ~= 1 then return false end
    if file == nil then
        return false
    end
    local contents = file:read("*a")
    if vim.fn.strptime(timeFmt, vim.fn.strftime(timeFmt)) - vim.fn.strptime(timeFmt, contents) > 10 * 60 then
        file:close()
        return true
    end
    file:close()
    return false
end

function M.isntReporting(index)
    local file = io.open(M.getLockFileName(index), "r")
    if file == nil then
        return false
    end
    local contents = file:read("*a")
    if vim.fn.strptime(timeFmt, vim.fn.strftime(timeFmt)) - vim.fn.strptime(timeFmt, contents) > 10 then
        file:close()
        return true
    end
    file:close()
    return false
end

function M.lockFileExists(index)
    local file = io.open(M.getLockFileName(index), "r")
    if file == nil then
        return false
    end
    file:close()
    return not M.isStale(index)
end

function M.isLowestLock()
    for i = 1, lockIndex - 1 do
        if M.lockFileExists(i) then
            return false
        end
    end
    return true
end

function M.forceClearLocks()
    for i = 1, lockIndex do
        if M.lockFileExists(i) then
            os.remove(M.getLockFileName(i))
        end
    end
end

function M.clearStaleLower()
    for i = 1, lockIndex do
        if M.lockFileExists(i) and M.isStale(i) then
            os.remove(M.getLockFileName(i))
        end
    end
end

function M.isPrimary()
    M.clearStaleLower()
    M.updateLock()
    return isPrimary
end

return M
