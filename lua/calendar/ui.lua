local bufnr = nil
local winnr = nil
local utils = require('calendar.utils')
local hlns = nil
local hlGroups = {}
local currentGroup = 0
local M = {}

---@class CalendarWord
---@field [1] string
---@field [2] table

function M.render()
    if bufnr == nil or not vim.api.nvim_buf_is_valid(bufnr) then
        bufnr = vim.api.nvim_create_buf(false, true)
    end
    if winnr == nil or not vim.api.nvim_win_is_valid(winnr) then
        winnr = vim.api.nvim_open_win(bufnr, true, {
            relative = "editor",
            width = vim.api.nvim_win_get_width(0) - 10,
            height = vim.api.nvim_win_get_height(0) - 10,
            row = 5,
            col = 5,
            style = "minimal"
        })
    end

    local data = require('calendar').readData()
    local events = {}
    local assignments = {}
    for _, event in ipairs(data.events) do
        if event.done == true then
            goto continue
        end
        events[#events + 1] = event
        ::continue::
    end
    for _, assignment in ipairs(data.assignments) do
        if assignment.done == true then
            goto continue
        end
        assignments[#assignments + 1] = assignment
        ::continue::
    end
    table.sort(events, function(a, b)
        return utils.absoluteTimeToSeconds(a.startTime) < utils.absoluteTimeToSeconds(b.startTime)
    end)
    table.sort(assignments, function(a, b)
        return utils.absoluteTimeToSeconds(a.due) < utils.absoluteTimeToSeconds(b.due)
    end)
    local allData = {}
    for _, event in ipairs(events) do
        allData[#allData + 1] = event
    end
    for _, assignment in ipairs(assignments) do
        allData[#allData + 1] = assignment
    end
    table.sort(allData, function(a, b)
        local aTime = a.type == "event" and a.startTime or a.due
        local bTime = b.type == "event" and b.startTime or b.due
        return utils.absoluteTimeToSeconds(aTime) < utils.absoluteTimeToSeconds(bTime)
    end)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
    ---@type CalendarWord[][]
    local lines = {}
    table.insert(lines, {
        { "Calendar" },
    })
    if require('calendar').isPrimary() then
        table.insert(lines, {
            { "Primary Instance", { link = "Title" } },
        })
    end
    table.insert(lines, {
    })
    -- vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, { "Calendar" })
    for _, d in ipairs(allData) do
        if d.type == "event" then
            ---@cast d CalendarEvent
            table.insert(lines, {
                { "Event: ", },
                { d.title,   { link = "Operator" } },
            })
            table.insert(lines, {
                { "   Start: ",                            { link = "Comment" } },
                { utils.absoluteTimeToPretty(d.startTime), { link = "String" } },
            })
            table.insert(lines, {
                { "   End: ",                            { link = "Comment" } },
                { utils.absoluteTimeToPretty(d.endTime), { link = "String" } },
            })
            table.insert(lines, {
                { "   Location: ", { link = "Comment" } },
                { d.location,      { link = "String" } },
            })
            if d.description ~= "" then
                table.insert(lines, {
                    { "   Description: ", { link = "Comment" } },
                    { d.description,      { link = "Comment" } },
                })
            end
            table.insert(lines, {
                { "   Warning: ", { link = "Comment" } },
                { d.warnTime,     { link = "Comment" } },
            })
            table.insert(lines, {
            })
        elseif d.type == "assignment" then
            ---@cast d CalendarAssignment
            table.insert(lines, {
                { "Assignment: " },
                { d.title,       { link = "Operator" } },
            })
            table.insert(lines, {
                { "   Due: " },
                { utils.absoluteTimeToPretty(d.due), { link = "String" } },
            })
            if d.description ~= "" then
                table.insert(lines, {
                    { "   Description: ", { link = "Comment" } },
                    { d.description,      { link = "Comment" } },
                })
            end
            table.insert(lines, {
                { "   Warning: ", { link = "Comment" } },
                { d.warnTime,     { link = "Comment" } },
            })
            table.insert(lines, {
                { "   Source: ",      { link = "Comment" } },
                { d.source or "None", { link = "Comment" } },
            })
            table.insert(lines, {
            })
        end
    end
    table.insert(lines, {
        { "Jobs" },
    })
    -- vim.api.nvim_buf_set_lines(bufnr, -1, -1, true, { "" })
    for _, d in ipairs(require('calendar').getRawData().jobs) do
        table.insert(lines, {
            { "Job: " },
            { d.id },
        })
        table.insert(lines, {
            { "   Running: " },
            { d.running and "Yes" or "No" },
        })
        table.insert(lines, {
            { "   Next Run: " },
            { utils.absoluteTimeToPretty(d.nextRun) },
        })
        -- vim.api.nvim_buf_set_lines(bufnr, -1, -1, true, {
        --     "Job: " .. d.id,
        --     "   Running: " .. (d.running and "Yes" or "No"),
        --     "   Next Run: " .. utils.absoluteTimeToPretty(d.nextRun),
        -- })
    end
    local linesToSet = {}
    for _, l in ipairs(lines) do
        local line = ""
        for _, word in ipairs(l) do
            line = line .. word[1]
        end
        linesToSet[#linesToSet + 1] = line
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, linesToSet)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    if hlns == nil then
        hlns = vim.api.nvim_create_namespace("calendar")
    end
    vim.api.nvim_win_set_buf(winnr, bufnr)
    vim.api.nvim_win_set_hl_ns(winnr, hlns)
    -- vim.api.nvim_win_set_option(winnr, "wrap", false)
    vim.api.nvim_win_set_option(winnr, "number", false)

    local line = 1
    for _, l in ipairs(lines) do
        local col = 0
        for _, word in ipairs(l) do
            if word[2] == nil then
                col = col + #word[1]
                goto continue
            end
            local hlGroupId = vim.inspect(word[2])
            if hlGroups[hlGroupId] == nil then
                hlGroups[hlGroupId] = "Calendar_" .. currentGroup
                vim.api.nvim_set_hl(hlns, "Calendar_" .. currentGroup, word[2])
                currentGroup = currentGroup + 1
            end
            local hlGroup = hlGroups[hlGroupId]
            vim.api.nvim_buf_add_highlight(bufnr, hlns, hlGroup, line - 1, col, col + #word[1])
            col = col + #word[1]
            ::continue::
        end
        line = line + 1
    end
end

function M.isRendering()
    return vim.api.nvim_get_current_buf() == bufnr
end

return M
