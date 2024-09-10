local M = {}

---@class (exact) Calendar.Lock
---@field id number
---@field reportTime string
---@field isThis boolean

local timeFmt = "%Y %b %d %X"
local promoteScheduled = false

---@type Calendar.Lock
local currentLock = {
    id = 0,
    reportTime = "",
    isThis = true,

}
local lockDir = ""
local dataPath = vim.fn.stdpath("data")

if type(dataPath) == "table" then
    lockDir = dataPath[1]
else
    lockDir = dataPath
end

---@class CalendarLockOptions
---@field lockDir string
local opts = {
    lockDir = lockDir,
}

function M.acquireLock()
    local i = 1
    while currentLock.id == 0 do
        if not M.lockExists(i) then
            currentLock.id = i
            break
        end
        i = i + 1
    end
    require("calendar.ui").refresh()
end

function M.getThisLockId()
    return currentLock.id
end

---@param options CalendarLockOptions
function M.setup(options)
    for key, _ in pairs(opts) do
        if options[key] ~= nil then
            opts[key] = options[key]
        end
    end
    M.acquireLock()
end

function M.killThisLock()
    M.killLock(currentLock.id)
end

function M.killLock(index)
    local name = M.getLockFileName(index)

    os.remove(name)
end

local function lockTryPromote()
    if M.isActingPrimary() and not promoteScheduled then
        promoteScheduled = true
        vim.defer_fn(function()
            promoteScheduled = false
            if M.isActingPrimary() then
                M.forceClearLocks()
            end
        end, currentLock.id * 10)
    end
end
function M.updateLock()
    lockTryPromote()
    local str = vim.fn.strftime(timeFmt)
    local file = io.open(M.getLockFileName(currentLock.id), 'w')
    if file == nil then
        print("cant write to lock file??")
        return
    end
    file:write(str)
    file:close()
end

---@param index number?
---@return string
function M.getLockFileName(index)
    if index == 0 then
        print("No index found")
        return ""
    end
    return opts.lockDir .. "/calendar_" .. index .. ".lock"
end

function M.getReportTime(index)
    local file = io.open(M.getLockFileName(index), "r")
    if file == nil then
        return 100000
    end
    local contents = file:read("*a")
    local time = vim.fn.strptime(timeFmt, contents)
    if time == 0 then
        file:close()
        return 0
    end
    local deadTime = vim.fn.strptime(timeFmt, vim.fn.strftime(timeFmt)) - time
    file:close()
    return deadTime
end

function M.maybeDead(index)
    return M.getReportTime(index) > 10
end

function M.killable(index)
    return M.getReportTime(index) > 3 * 60
end

function M.getTakeOver()
    local takeOver = 0
    for i = 1, currentLock.id - 1 do
        local nextTime = 3 * 60 - M.getReportTime(i)
        takeOver = math.max(takeOver, nextTime)
    end
    return takeOver
end

function M.isMaybeActingPrimary()
    if M.isPrimary() then return false end
    for i = 1, currentLock.id - 1 do
        if M.lockExists(i) and not M.maybeDead(i) then
            return false
        end
    end
    return true
end

function M.lockExists(index)
    local file = io.open(M.getLockFileName(index), "r")
    if file == nil then
        return false
    end
    file:close()
    return true
end

function M.isActingPrimary()
    if M.isPrimary() then return false end
    for i = 1, currentLock.id - 1 do
        if M.lockExists(i) and not M.killable(i) then
            return false
        end
    end
    return true
end

function M.isPrimary()
    return currentLock.id == 1
end

function M.forceClearLocks()
    for i = 1, currentLock.id do
        M.killLock(i)
    end
    currentLock.id = 0
    M.acquireLock()
end

return M
