local M = {}

---@alias CalendarAbsoluteTime string|integer
---@alias CalendarRelativeTime string|integer

---@class (exact) CalendarEvent
---@field title string
---@field description string
---@field location string?
---@field startTime CalendarAbsoluteTime
---@field endTime CalendarAbsoluteTime
---@field warnTime CalendarRelativeTime
---@field type "event"
---@field done boolean?
---@field source string?

---@class (exact) CalendarAssignment
---@field title string
---@field description string
---@field due CalendarAbsoluteTime
---@field warnTime CalendarRelativeTime
---@field type "assignment"
---@field source string?
---@field done boolean?

---@alias CalendarImport fun(data: table, success: fun(), fail: fun())

---@class (exact) CalendarImportOptions
---@field fn CalendarImport
---@field runFrequency integer|string
---@field id string

---@class (exact) CalendarJobData
---@field id string
---@field lastRun integer
---@field nextRun integer
---@field running boolean

---@class (exact) CalendarOptions
---@field import? CalendarImportOptions[]
---@field dataLocation? string
---@field dateFormat? string
---@field lockFile? string
local opts = {
    import = {},
    dataLocation = vim.fn.stdpath("data") .. "/calendar.json",
    dateFormat = "%Y-%m-%d %H:%M:%S",
    lockFile = vim.fn.stdpath("data") .. "/calendar.lock"
}
function M.basicRawData()
    return {
        events = {},
        assignments = {},
        jobs = {}
    }
end

local isPrimary = false
local lockIndex = 0

---@type string[]
--The jobs that are currently being ran by this instance
local ownedJobs = {}

local utils = require('calendar.utils')

---@class (exact) CalendarRawData
---@field events CalendarEvent[]
---@field assignments CalendarAssignment[]
---@field jobs CalendarJobData[]

---@type CalendarRawData
local rawData = M.basicRawData()

---@param o CalendarOptions
function M.setup(o)
    opts = vim.tbl_extend("force", opts, o)
    vim.api.nvim_create_user_command("Calendar", function(cmdOpts)
        if cmdOpts.fargs == nil or #cmdOpts.fargs then
            require('calendar.ui').render()
        end
        if cmdOpts.fargs[1] == "remove" then
            require('calendar').markDone(cmdOpts.fargs[2])
        end
    end, {
        nargs = "*"

    })
    M.readData()
    M.syncJobsTracked()
    M.saveData(rawData)
    vim.api.nvim_create_autocmd({ "QuitPre" }, {
        callback = function()
            for _, job in ipairs(ownedJobs) do
                for i, trackedJob in ipairs(rawData.jobs) do
                    if trackedJob.id == job then
                        rawData.jobs[i].running = false
                        rawData.jobs[i].nextRun = 0
                        rawData.jobs[i].lastRun = os.time()
                        break
                    end
                end
            end
            M.saveData(rawData)
            --- Remove the index from the lock file
            local lockFile = io.open(opts.lockFile, "r")
            if lockFile == nil then
                error("Could not open lock file for reading")
            end
            local lines = {}
            for line in lockFile:lines() do
                lines[#lines + 1] = line
            end
            lockFile:close()
            for i = #lines, 1, -1 do
                if tonumber(lines[i]) == lockIndex then
                    table.remove(lines, i)
                    break
                end
            end
            for i, line in ipairs(lines) do
                if tonumber(line) == lockIndex then
                    table.remove(lines, i)
                    break
                end
            end
            lockFile = io.open(opts.lockFile, "w")
            if lockFile == nil then
                error("Could not open lock file for writing")
            end
            for _, line in ipairs(lines) do
                lockFile:write(line .. "\n")
            end
            lockFile:close()
        end
    })

    local lockFile = io.open(opts.lockFile, "r")
    if lockFile == nil then
        lockFile = io.open(opts.lockFile, "w")
        if lockFile == nil then
            error("Could not open lock file for reading or writing")
        end
        lockFile:write("1")
        lockFile:close()
        lockIndex = 1
        isPrimary = true
    else
        --basically read the entire file (1 number per line) add 1 to the maximum number, and append that to the file
        --then set isPrimary to false
        local lines = {}
        for line in lockFile:lines() do
            lines[#lines + 1] = line
        end
        lockFile:close()
        for _, line in ipairs(lines) do
            local num = tonumber(line) or 0
            if num > lockIndex then
                lockIndex = num
            end
        end
        lockIndex = lockIndex + 1
        lockFile = io.open(opts.lockFile, "w")
        if lockFile == nil then
            error("Could not open lock file for writing")
        end
        lines[#lines + 1] = lockIndex
        for _, line in ipairs(lines) do
            lockFile:write(line .. "\n")
        end
        lockFile:close()
    end
end

function M.isPrimary()
    return isPrimary
end

function M.updatePrimary()
    if isPrimary then
        return
    end
    local lockFile = io.open(opts.lockFile, "r")
    if lockFile == nil then
        error("Could not open lock file for reading")
    end
    local lines = {}
    for line in lockFile:lines() do
        lines[#lines + 1] = line
    end
    lockFile:close()
    for i = #lines, 1, -1 do
        if tonumber(lines[i]) == nil then
            table.remove(lines, i)
        end
    end
    lockFile = io.open(opts.lockFile, "w")
    if lockFile == nil then
        error("Could not open lock file for writing")
    end
    for _, line in ipairs(lines) do
        lockFile:write(line .. "\n")
    end
    lockFile:close()
    if tonumber(lines[1]) == lockIndex then
        isPrimary = true
    end
end

function M.getOpts()
    return opts
end

function M.validateAbsoluteTime(time)
    if type(time) == "string" then
        return ""
    end
    if type(time) == "number" then
        return ""
    end
    return "Time must be a string or a number"
end

function M.validateRelativeTime(time)
    if type(time) == "string" then
        return ""
    end
    if type(time) == "number" then
        return ""
    end
    return "Time must be a string or a number"
end

---@param e CalendarEvent
---@return string
function M.validateEvent(e)
    if type(e.title) ~= "string" then
        return "Title must be a string"
    end
    if type(e.description) ~= "string" then
        return "Description must be a string"
    end

    local validateStart = M.validateAbsoluteTime(e.startTime)
    if validateStart ~= '' then
        return "Start " .. validateStart
    end

    local validateEnd = M.validateAbsoluteTime(e.endTime)
    if validateEnd ~= '' then
        return "End " .. validateEnd
    end

    local validateWarn = M.validateRelativeTime(e.warnTime)
    if validateWarn ~= '' then
        return "Warn " .. validateWarn
    end

    if type(e.type) ~= "string" then
        return "Type must be a string"
    end
    if e.type ~= "event" then
        return "Type must be 'event'"
    end
    return ''
end

---@param a CalendarAssignment
---@return string
function M.validateAssignment(a)
    if type(a.title) ~= "string" then
        return "Title must be a string"
    end
    if type(a.description) ~= "string" then
        return "Description must be a string"
    end
    local validateDue = M.validateAbsoluteTime(a.due)
    if validateDue ~= '' then
        return "Due " .. validateDue
    end
    local validateWarn = M.validateRelativeTime(a.warnTime)
    if validateWarn ~= '' then
        return "Warn " .. validateWarn
    end
    if type(a.type) ~= "string" then
        return "Type must be a string"
    end
    if a.type ~= "assignment" then
        return "Type must be 'assignment'"
    end
    return ''
end

function M.addEvent(event)
    local validate = M.validateEvent(event)
    if validate ~= '' then
        return validate
    end
    for i, e in ipairs(rawData.events) do
        if e.title == event.title then
            rawData.events[i] = event
            return M.saveData(rawData)
        end
    end
    table.insert(rawData.events, event)
    return M.saveData(rawData)
end

function M.inputEvent()
    local title = vim.fn.input("Title: ")
    local description = vim.fn.input("Description: ")
    local location = vim.fn.input("Location: ")
    local startTime = vim.fn.input("Start Time: ")
    local endTime = vim.fn.input("End Time: ")
    local warnTime = vim.fn.input("Warn Time: ")
    local type = "event"
    local done = false
    local source = "manual"
    local event = {
        title = title,
        description = description,
        location = location,
        startTime = startTime,
        endTime = endTime,
        warnTime = warnTime,
        type = type,
        done = done,
        source = source
    }
    M.addEvent(event)
end

function M.inputAssignment()
    local title = vim.fn.input("Title: ")
    local description = vim.fn.input("Description: ")
    local due = vim.fn.input("Due: ")
    local warnTime = vim.fn.input("Warn Time: ")
    local type = "assignment"
    local done = false
    local source = "manual"
    local assignment = {
        title = title,
        description = description,
        due = due,
        warnTime = warnTime,
        type = type,
        done = done,
        source = source
    }
    M.addAssignment(assignment)
end

function M.addAssignment(assignment)
    local validate = M.validateAssignment(assignment)
    if validate ~= '' then
        error(validate)
    end
    for i, a in ipairs(rawData.assignments) do
        if a.title == assignment.title then
            rawData.assignments[i] = assignment
            return M.saveData(rawData)
        end
    end
    table.insert(rawData.assignments, assignment)
    return M.saveData(rawData)
end

---@return CalendarAssignment[]
function M.getAssignmentsToWorryAbout()
    M.updatePrimary()
    M.readData()
    M.clearPast()
    local now = os.time()
    local events = {}
    for _, assignment in ipairs(rawData.assignments) do
        local warnTime = utils.relativeTimeToSeconds(assignment.warnTime)
        if assignment.done ~= true and warnTime > 0 and utils.absoluteTimeToSeconds(assignment.due) - now <= warnTime then
            events[#events + 1] = assignment
        end
    end
    return events
end

---@return CalendarEvent[]
function M.getEventsToWorryAbout()
    M.updatePrimary()
    M.readData()
    M.clearPast()
    local now = os.time()
    local events = {}
    for _, event in ipairs(rawData.events) do
        local warnTime = utils.relativeTimeToSeconds(event.warnTime)
        if event.done ~= true and warnTime > 0 and utils.absoluteTimeToSeconds(event.startTime) - now <= warnTime then
            events[#events + 1] = event
        end
    end
    return events
end

---@return (CalendarEvent | CalendarAssignment)[]
function M.getStuffToWorryAbout()
    M.clearPast()
    -- M.readData()
    local now = os.time()
    local events = {}
    for _, event in ipairs(rawData.events) do
        local warnTime = utils.relativeTimeToSeconds(event.warnTime)
        if event.done ~= true and warnTime > 0 and utils.absoluteTimeToSeconds(event.startTime) - now <= warnTime then
            events[#events + 1] = event
        end
    end
    for _, assignment in ipairs(rawData.assignments) do
        local warnTime = utils.relativeTimeToSeconds(assignment.warnTime)
        if assignment.done ~= true and warnTime > 0 and utils.absoluteTimeToSeconds(assignment.due) - now <= warnTime then
            events[#events + 1] = assignment
        end
    end
    return events
end

function M.clearPast()
    -- M.readData()
    local now = os.time()
    local newEvents = {}
    for _, event in ipairs(rawData.events) do
        if utils.absoluteTimeToSeconds(event.endTime) >= now then
            newEvents[#newEvents + 1] = event
        end
    end
    rawData.events = newEvents
    local newAssignments = {}
    for _, assignment in ipairs(rawData.assignments) do
        if utils.absoluteTimeToSeconds(assignment.due) >= now then
            newAssignments[#newAssignments + 1] = assignment
        end
    end
    rawData.assignments = newAssignments
    M.saveData(rawData)
    return rawData
end

function M.markDone(name)
    for i, event in ipairs(rawData.events) do
        if event.title == name then
            rawData.events[i].done = true
            print("Event " .. name .. " marked as done")
            M.saveData(rawData)
            return
        end
    end
    for i, assignment in ipairs(rawData.assignments) do
        if assignment.title == name then
            rawData.assignments[i].done = true
            print("Assignment " .. name .. " marked as done")
            M.saveData(rawData)
            return
        end
    end
end

function M.runJob(id, force)
    if not isPrimary then
        return
    end
    for _, job in ipairs(opts.import) do
        if job.id == id then
            for i, trackedJob in ipairs(rawData.jobs) do
                if trackedJob.id == id then
                    if trackedJob.running and not force then
                        return
                    end
                    rawData.jobs[i].running = true
                    M.saveData(rawData)
                    break
                end
            end
            ownedJobs[#ownedJobs + 1] = id
            local fail = function()
                for i, trackedJob in ipairs(rawData.jobs) do
                    if trackedJob.id == id then
                        rawData.jobs[i].running = false
                        rawData.jobs[i].nextRun = 0
                        rawData.jobs[i].lastRun = os.time()
                        for j, ownedJob in ipairs(ownedJobs) do
                            if ownedJob == id then
                                table.remove(ownedJobs, j)
                                break
                            end
                        end
                        M.saveData(rawData)
                        break
                    end
                end
            end
            local ok, _ = pcall(job.fn, {}, function()
                for i, trackedJob in ipairs(rawData.jobs) do
                    if trackedJob.id == id then
                        rawData.jobs[i].running = false
                        rawData.jobs[i].lastRun = os.time()
                        rawData.jobs[i].nextRun = os.time() + utils.relativeTimeToSeconds(job.runFrequency)
                        for j, ownedJob in ipairs(ownedJobs) do
                            if ownedJob == id then
                                table.remove(ownedJobs, j)
                                break
                            end
                        end
                        M.saveData(rawData)
                        break
                    end
                end
            end, fail)
            if not ok then
                fail()
            end
            return
        end
    end
end

function M.syncJobsTracked()
    for _, job in ipairs(opts.import) do
        local found = false
        for _, trackedJob in ipairs(rawData.jobs) do
            if trackedJob.id == job.id then
                found = true
                break
            end
        end
        if not found then
            -- print("Adding job " .. job.id)
            rawData.jobs[#rawData.jobs + 1] = {
                id = job.id,
                lastRun = 0,
                nextRun = 0,
                running = false
            }
            -- M.saveData(rawData)
        end
    end
    for _ = 1, #rawData.jobs do
        for _, job in ipairs(rawData.jobs) do
            local found = false
            for _, trackedJob in ipairs(opts.import) do
                if trackedJob.id == job.id then
                    found = true
                    break
                end
            end
            if not found then
                for i, trackedJob in ipairs(rawData.jobs) do
                    if trackedJob.id == job.id then
                        table.remove(rawData.jobs, i)
                        break
                    end
                end
                break
            end
        end
    end
    -- print(vim.inspect(rawData))
    M.saveData(rawData)
    M.readData()
end

function M.checkJobsTracked()
    for _, job in ipairs(rawData.jobs) do
        if job.nextRun <= os.time() then
            M.runJob(job.id)
        end
    end
end

function M.getRawData()
    return rawData
end

function M.readData()
    if isPrimary then
        return rawData
    end
    local file = io.open(opts.dataLocation, "r")
    if file == nil then
        file = io.open(opts.dataLocation, "w")
        if file == nil then
            error("Could not open file for reading or writing")
        end
        file:write("{}")
        file:close()
        file = io.open(opts.dataLocation, "r")
    end
    if file == nil then
        error("Could not open file for reading")
    end
    local contents = file:read("*all")
    if contents == "" then
        contents = "{}"
    end
    local ok, data = pcall(vim.json.decode, contents)
    if not ok then
        print("Error decoding json")
        rawData = M.basicRawData()
        return rawData
    end
    file:close()
    rawData = vim.tbl_extend("force", M.basicRawData(), data)

    vim.schedule(function()
        M.checkJobsTracked()
    end)

    return rawData
end

function M.saveData(data)
    if not isPrimary then
        return
    end
    local file = io.open(opts.dataLocation, "w")
    if file == nil then
        return "Could not open file for writing"
    end

    file:write(vim.json.encode(data))
    file:close()
    return ""
end

return M
