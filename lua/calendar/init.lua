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

---@alias CalendarImport fun(data: table, success: fun())

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
local opts = {
    import = {},
    dataLocation = vim.fn.stdpath("data") .. "/calendar.json",
    dateFormat = "%Y-%m-%d %H:%M:%S",
}
function M.basicRawData()
    return {
        events = {},
        assignments = {},
        jobs = {}
    }
end

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
    -- M.readData()
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
    -- M.readData()
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

function M.runJob(id)
    for _, job in ipairs(opts.import) do
        if job.id == id then
            job.fn({}, function()
                for i, trackedJob in ipairs(rawData.jobs) do
                    if trackedJob.id == id then
                        rawData.jobs[i].lastRun = os.time()
                        rawData.jobs[i].nextRun = os.time() + utils.relativeTimeToSeconds(job.runFrequency)
                        M.saveData(rawData)
                        break
                    end
                end
            end)
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
    for i, job in ipairs(rawData.jobs) do
        if job.nextRun <= os.time() then
            for _, import in ipairs(opts.import) do
                if import.id == job.id then
                    import.fn({}, function()
                        rawData.jobs[i].lastRun = os.time()
                        rawData.jobs[i].nextRun = os.time() + utils.relativeTimeToSeconds(import.runFrequency)
                        rawData.jobs[i].running = false
                        M.saveData(rawData)
                    end)
                    job.nextRun = os.time() + 1000000000000
                    job.running = true
                    M.saveData(rawData)
                    break
                end
            end
        end
    end
end

function M.getRawData()
    return rawData
end

function M.readData()
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
    local file = io.open(opts.dataLocation, "w")
    if file == nil then
        print("sdfsdf")
        error('sadf')
        return "Could not open file for writing"
        -- error("Could not open file for writing")
    end

    file:write(vim.json.encode(data))
    file:close()
    return ""
end

return M
