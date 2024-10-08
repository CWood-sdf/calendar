local M = {}

local lock = require("calendar.lock")
local mods = {
    validate = require("calendar.validate"),
}
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

---@class CalendarOptions
---@field import CalendarImportOptions[]
---@field dataLocation string
---@field dateFormat string
---@field requestFile string
local opts = {
    import = {},
    dataLocation = vim.fn.stdpath("data") .. "/calendar.json",
    dateFormat = "%Y-%m-%d %H:%M:%S",
    requestFile = vim.fn.stdpath("data") .. "/calendar_requests.json",
}

---@class CalendarSetupOptions: CalendarOptions, CalendarLockOptions

---@class (exact) CalendarRequest
---@field type "runJob"|"markDone"|"addEvent"|"addAssignment"|"timezoneShift"|"delete"|"resurrect"
---@field name string?
---@field data table?

function M.basicRawData()
    return {
        events = {},
        assignments = {},
        jobs = {},
    }
end

---@type string[]
--The jobs that are currently being ran by this instance
local ownedJobs = {}

local utils = require("calendar.utils")

---@class (exact) CalendarRawData
---@field events CalendarEvent[]
---@field assignments CalendarAssignment[]
---@field jobs CalendarJobData[]

---@type CalendarRawData
local rawData = M.basicRawData()
local lastRawData = M.basicRawData()

---@param r CalendarRequest
function M.handleRequest(r)
    if not lock.isPrimary() then
        return
    end
    -- print("Handling request for " .. r.type)
    if r.type == "runJob" then
        M.runJob(r.name, true)
    elseif r.type == "markDone" then
        M.markDone(r.name)
    elseif r.type == "addEvent" then
        M.addEvent(r.data)
    elseif r.type == "addAssignment" then
        M.addAssignment(r.data)
    elseif r.type == "delete" then
        M.delete(r.name)
    elseif r.type == "timezoneShift" then
        M.timezoneShift(r.data[1])
    elseif r.type == "resurrect" then
        M.resurrect(r.name)
    else
        print("Invalid request type " .. r.type)
    end
end

function M.checkRequestFile()
    if not lock.isPrimary() then
        return false
    end
    local file = io.open(opts.requestFile, "r")
    if file == nil then
        return false
    end
    local contents = file:read("*all")
    file:close()
    if contents == "" then
        return false
    end
    local ok, data = pcall(vim.json.decode, contents)
    if not ok then
        return false
    end
    data = data or {}
    os.remove(opts.requestFile)
    for _, r in ipairs(data) do
        M.handleRequest(r)
    end
    return true
end

---@param r CalendarRequest
function M.addRequest(r)
    if lock.isPrimary() then
        return
    end
    print("Adding request for " .. r.type)
    local file = io.open(opts.requestFile, "r")
    if file == nil then
        file = io.open(opts.requestFile, "w")
        if file == nil then
            error("Could not open file for reading or writing")
        end
        file:write(vim.json.encode({ r }))
        file:close()
        return
    end
    local contents = file:read("*all")
    file:close()
    local ok, data = pcall(vim.json.decode, contents)
    if not ok then
        data = {}
    end
    data = data or {}
    data[#data + 1] = r
    file = io.open(opts.requestFile, "w")
    if file == nil then
        error("Could not open file for writing")
    end
    file:write(vim.json.encode(data))
    file:close()
end

---@return string
---Turns an event name into a command name by replacing ' ' with '-'
---@param name string
function M.getCommandName(name)
    local str, _ = string.gsub(name, " ", "-")
    return str
end

---@param name string
---@return CalendarEvent|CalendarAssignment?
function M.getEventOrAssignmentFromCommandName(name)
    for _, event in ipairs(rawData.events) do
        if M.getCommandName(event.title) == name then
            return event
        end
    end
    for _, assignment in ipairs(rawData.assignments) do
        if M.getCommandName(assignment.title) == name then
            return assignment
        end
    end
    return nil
end

local ct = require("cmdTree")
local getEventsOrAssignments = ct.requiredParams(function()
    local ret = {}
    for _, event in ipairs(rawData.events) do
        if not event.done then
            ret[#ret + 1] = M.getCommandName(event.title)
        end
    end
    for _, assignment in ipairs(rawData.assignments) do
        if not assignment.done then
            ret[#ret + 1] = M.getCommandName(assignment.title)
        end
    end
    return ret
end)

local commandTree = {
    Calendar = {
        _callback = function()
            require("calendar.ui").render()
        end,
        parseThisBuf = {
            _callback = function()
                local buf = vim.api.nvim_get_current_buf()
                require('calendar.bufferreader').parseBuf(buf)
            end,
        },
        resurrect = {
            ct.requiredParams(function()
                local ret = {}
                for _, event in ipairs(rawData.events) do
                    if event.done then
                        ret[#ret + 1] = M.getCommandName(event.title)
                    end
                end
                for _, assignment in ipairs(rawData.assignments) do
                    if assignment.done then
                        ret[#ret + 1] = M.getCommandName(assignment.title)
                    end
                end
                return ret
            end),
            _callback = function(args)
                local name = M.getEventOrAssignmentFromCommandName(args.params[1][1]).title
                M.resurrect(name)
            end,
        },
        runJob = {

            ct.requiredParams(function()
                local ret = {}
                for _, job in ipairs(rawData.jobs) do
                    ret[#ret + 1] = job.id
                end
                return ret
            end),
            ct.optionalParams(function()
                return { "force" }
            end),
            _callback = function(args)
                local secondParam = (args.params[2] or {})[1] or ""
                M.runJob(args.params[1][1], secondParam ~= "")
            end,
        },
        shiftTimezone = {
            _callback = function(args)
                local delta = ""
                if args.params[1] == nil or args.params[1][1] == nil then
                    delta = vim.fn.input("Delta: ")
                else
                    delta = args.params[1][1]
                end
                M.timezoneShift(delta)
            end,
        },
        forceClearLocks = {
            _callback = function()
                lock.forceClearLocks()
            end,
        },
        assigment = {
            input = {
                _callback = function()
                    M.inputAssignment()
                end,
            },
            modify = {
                ct.requiredParams(function()
                    local ret = {}
                    for _, assignment in ipairs(rawData.assignments) do
                        if not assignment.done then
                            ret[#ret + 1] = M.getCommandName(assignment.title)
                        end
                    end
                    return ret
                end),
                _callback = function(args)
                    local name = args.params[1][1]
                    M.modifyAssignment(M.getEventOrAssignmentFromCommandName(name))
                end,
            },
        },
        event = {
            input = {
                _callback = function()
                    M.inputEvent()
                end,
            },
            modify = {
                ct.requiredParams(function()
                    local ret = {}
                    for _, event in ipairs(rawData.events) do
                        if not event.done then
                            ret[#ret + 1] = M.getCommandName(event.title)
                        end
                    end
                    return ret
                end),
                _callback = function(args)
                    local name = args.params[1][1]
                    M.modifyEvent(M.getEventOrAssignmentFromCommandName(name))
                end,
            },
        },
        remove = {
            getEventsOrAssignments,
            _callback = function(args)
                local name = args.params[1][1]
                M.markDone(M.getEventOrAssignmentFromCommandName(name).title)
            end,
        },
        delete = {
            ct.requiredParams(function()
                local ret = {}
                for _, event in ipairs(rawData.events) do
                    ret[#ret + 1] = M.getCommandName(event.title)
                end
                for _, assignment in ipairs(rawData.assignments) do
                    ret[#ret + 1] = M.getCommandName(assignment.title)
                end
                return ret
            end),
            _callback = function(args)
                local name = args.params[1][1]
                M.delete(M.getEventOrAssignmentFromCommandName(name).title)
            end,
        },
    },
}

function M.createCalendarCommand()
    ct.createCmd(commandTree, {})
end

---@param o CalendarLockOptions
function M.setup(o)
    opts = vim.tbl_extend("force", opts, o)
    lock.setup(opts)
    M.readData(true)
    M.createCalendarCommand()
    vim.api.nvim_create_autocmd({ "VimLeavePre" }, {
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
            lock.killThisLock()
        end,
    })

    M.syncJobsTracked()
end

function M.updatePrimary()
    lock.updateLock()
end

function M.getOpts()
    return opts
end

---@param prompt string
---@param default string
---@return string
local function getInputDefault(prompt, default)
    local input = vim.fn.input(prompt .. " (" .. default .. "): ")
    if input == "" then
        return default .. ""
    end
    return input .. ""
end

---@param e CalendarEvent|CalendarAssignment?
function M.modifyEvent(e)
    if e == nil then
        return
    end
    if e.type == "assignment" then
        print("assignment passed to modifyEvent")
        return
    end
    local event = nil
    for _, ev in ipairs(rawData.events) do
        if ev.title == e.title then
            event = ev
            break
        end
    end
    if event == nil then
        return
    end
    local description = getInputDefault("Description", event.description)
    local location = getInputDefault("Location", event.location)
    ---@type string|integer
    local startTime = getInputDefault("Start Time", event.startTime)
    if startTime:sub(1, 1) == "+" then
        startTime = os.time() + utils.relativeTimeToSeconds(startTime:sub(2))
    end
    ---@type string|integer
    local endTime = getInputDefault("End Time", event.endTime)
    if endTime:sub(1, 1) == "+" then
        endTime = os.time() + utils.relativeTimeToSeconds(endTime:sub(2))
    end
    local warnTime = getInputDefault("Warn Time", event.warnTime)
    local type = "event"
    local done = false
    local source = event.source
    local newEvent = {
        title = event.title,
        description = description,
        location = location,
        startTime = startTime,
        endTime = endTime,
        warnTime = warnTime,
        type = type,
        done = done,
        source = source,
    }
    M.addEvent(newEvent)
end

---@param event CalendarEvent
function M.addEvent(event)
    event.type = "event"
    local validate = mods.validate.event(event)
    if validate ~= "" then
        print(validate)
        return validate
    end
    if not lock.isPrimary() then
        M.addRequest({
            type = "addEvent",
            data = event,
        })
        return
    end
    for i, e in ipairs(rawData.events) do
        if e.title == event.title then
            rawData.events[i] = event
            -- rawData.events[i].done = false
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
    ---@type string|integer
    local startTime = vim.fn.input("Start Time: ")
    if startTime:sub(1, 1) == "+" then
        startTime = (os.time() + utils.relativeTimeToSeconds(startTime:sub(2)))
    end
    ---@type string|integer
    local endTime = vim.fn.input("End Time: ")
    if endTime:sub(1, 1) == "+" then
        endTime = os.time() + utils.relativeTimeToSeconds(endTime:sub(2))
    end
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
        source = source,
    }
    M.addEvent(event)
end

function M.inputAssignment()
    local title = vim.fn.input("Title: ")
    local description = vim.fn.input("Description: ")
    ---@type string|integer
    local due = vim.fn.input("Due: ")
    if due:sub(1, 1) == "+" then
        -- print(due:sub(2))
        due = os.time() + utils.relativeTimeToSeconds(due:sub(2))
    end
    local warnTime = vim.fn.input("Warn Time: ")
    local type = "assignment"
    local done = false
    local source = "manual"
    ---@type CalendarAssignment
    local assignment = {
        title = title,
        description = description,
        due = due,
        warnTime = warnTime,
        type = type,
        done = done,
        source = source,
    }
    M.addAssignment(assignment)
end

---@param a CalendarAssignment|CalendarEvent?
function M.modifyAssignment(a)
    if a == nil then
        print("Assignment not found")
        return
    end
    if a.type == "event" then
        print("event passed to modifyAssignment")
        return
    end
    local assignment = nil
    for _, as in ipairs(rawData.assignments) do
        if as.title == a.title then
            assignment = as
            break
        end
    end
    if assignment == nil then
        return
    end
    local description = getInputDefault("Description", assignment.description)
    ---@type string|integer
    local due = getInputDefault("Due", assignment.due)
    if due:sub(1, 1) == "+" then
        due = os.time() + utils.relativeTimeToSeconds(due:sub(2))
    end
    local warnTime = getInputDefault("Warn Time", assignment.warnTime)
    local type = "assignment"
    local done = false
    local source = assignment.source
    local newAssignment = {
        title = assignment.title,
        description = description,
        due = due,
        warnTime = warnTime,
        type = type,
        done = done,
        source = source,
    }
    M.addAssignment(newAssignment)
end

---@param assignment CalendarAssignment
function M.addAssignment(assignment)
    assignment.type = "assignment"
    local validate = mods.validate.assignment(assignment)
    if validate ~= "" then
        error(validate)
    end
    if not lock.isPrimary() then
        M.addRequest({
            type = "addAssignment",
            data = assignment,
        })
        return
    end
    for i, a in ipairs(rawData.assignments) do
        if a.title == assignment.title then
            rawData.assignments[i] = vim.tbl_extend("force", rawData.assignments[i], assignment)
            -- rawData.assignments[i].done = false
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
        if
            assignment.done ~= true
            and warnTime > 0
            and utils.absoluteTimeToSeconds(assignment.due) - now <= warnTime
        then
            events[#events + 1] = assignment
        end
    end
    return events
end

---@return CalendarEvent[]
function M.getEventsToWorryAbout()
    M.readData()
    M.updateForPrimary()
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
    M.readData()
    M.updateForPrimary()
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
        if
            assignment.done ~= true
            and warnTime > 0
            and utils.absoluteTimeToSeconds(assignment.due) - now <= warnTime
        then
            events[#events + 1] = assignment
        end
    end
    return events
end

function M.clearPast()
    if not lock.isPrimary() then
        return
    end
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

function M.updateForPrimary()
    if not lock.isPrimary() then
        return
    end
    M.checkRequestFile()
    M.checkJobsTracked()
    M.clearPast()
end

function M.markDone(name)
    if not lock.isPrimary() then
        -- print("Not primary")
        M.addRequest({
            type = "markDone",
            name = name,
        })
        return
    end
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

function M.resurrect(name)
    if not lock.isPrimary() then
        -- print("Not primary")
        M.addRequest({
            type = "resurrect",
            name = name,
        })
        return
    end
    for i, event in ipairs(rawData.events) do
        if event.title == name then
            rawData.events[i].done = false
            print("Event " .. name .. " marked as not done")
            M.saveData(rawData)
            return
        end
    end
    for i, assignment in ipairs(rawData.assignments) do
        if assignment.title == name then
            rawData.assignments[i].done = false
            print("Assignment " .. name .. " marked as not done")
            M.saveData(rawData)
            return
        end
    end
end

---@param delta integer|string
--Shift all times by delta seconds
function M.timezoneShift(delta)
    if not lock.isPrimary() then
        -- print("Not primary")
        M.addRequest({
            type = "timezoneShift",
            data = { delta },
        })
        return
    end
    delta = utils.relativeTimeToSeconds(delta)
    for _, event in ipairs(rawData.events) do
        event.startTime = utils.absoluteTimeToSeconds(event.startTime) + delta
        event.endTime = utils.absoluteTimeToSeconds(event.endTime) + delta
    end
    for _, assignment in ipairs(rawData.assignments) do
        assignment.due = utils.absoluteTimeToSeconds(assignment.due) + delta
    end
    for _, job in ipairs(rawData.jobs) do
        job.lastRun = job.lastRun + delta
        job.nextRun = job.nextRun + delta
    end
    M.saveData(rawData)
end

---@param id string
function M.delete(id)
    if not lock.isPrimary() then
        M.addRequest({
            type = "delete",
            name = id,
        })
        return
    end
    for i, event in ipairs(rawData.events) do
        if event.title == id then
            print("Deleting event " .. id)
            table.remove(rawData.events, i)
            M.saveData(rawData)
            return
        end
    end
    for i, assignment in ipairs(rawData.assignments) do
        if assignment.title == id then
            print("Deleting assignment " .. id)
            table.remove(rawData.assignments, i)
            M.saveData(rawData)
            return
        end
    end
end

function M.runJob(id, force)
    if not lock.isPrimary() then
        -- print("Not primary")
        M.addRequest({
            type = "runJob",
            name = id,
        })
        return
    end
    -- print("attempting to run job " .u id)
    for _, job in ipairs(opts.import) do
        if job.id == id then
            for i, trackedJob in ipairs(rawData.jobs) do
                if trackedJob.id == id then
                    if trackedJob.running and not force then
                        print("Job " .. id .. " already running")
                        return
                    end
                    print("Running job " .. id)
                    rawData.jobs[i].running = true
                    rawData.jobs[i].lastRun = os.time()
                    if job.runFrequency:sub(1, 1) == "c" then
                        local cron = require("calendar.cron")
                        local str = job.runFrequency:sub(2)
                        local parsed = cron.parse(str)
                        if parsed == nil then
                            print("Invalid cron string " .. str)
                            return
                        end
                        local nextRun = cron.nextOccurence(parsed)
                        rawData.jobs[i].nextRun = nextRun
                    else
                        rawData.jobs[i].nextRun = os.time() + utils.relativeTimeToSeconds(job.runFrequency)
                    end
                    M.saveData(rawData)
                    break
                end
            end
            ownedJobs[#ownedJobs + 1] = id
            local fail = function()
                for i, trackedJob in ipairs(rawData.jobs) do
                    if trackedJob.id == id then
                        print("Job " .. id .. " failed")
                        rawData.jobs[i].running = false
                        rawData.jobs[i].nextRun = os.time() + 60
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
                        print("Job " .. id .. " succeeded")
                        rawData.jobs[i].running = false
                        rawData.jobs[i].lastRun = os.time()
                        if job.runFrequency:sub(1, 1) == "c" then
                            local cron = require("calendar.cron")
                            local str = job.runFrequency:sub(2)
                            local parsed = cron.parse(str)
                            if parsed == nil then
                                print("Invalid cron string " .. str)
                                return
                            end
                            local nextRun = cron.nextOccurence(parsed)
                            rawData.jobs[i].nextRun = nextRun
                        else
                            rawData.jobs[i].nextRun = os.time() + utils.relativeTimeToSeconds(job.runFrequency)
                        end
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
                running = false,
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
    -- M.readData()
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

function M.readData(force)
    if lock.isPrimary() and not force then
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
    local oldRawData = vim.deepcopy(rawData)
    rawData = vim.tbl_extend("force", M.basicRawData(), data)
    if vim.inspect(oldRawData) ~= vim.inspect(rawData) then
        require("calendar.ui").refresh()
    end

    return rawData
end

function M.saveData(data)
    if not lock.isPrimary() then
        return
    end
    if vim.inspect(lastRawData) == vim.inspect(data) then
        return
    end
    lastRawData = vim.deepcopy(data)
    require("calendar.ui").refresh()
    local file = io.open(opts.dataLocation, "w")
    if file == nil then
        return "Could not open file for writing"
    end

    file:write(vim.json.encode(data))
    file:close()
    return ""
end

return M
