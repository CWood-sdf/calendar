local bufnr = nil
local winnr = nil
local utils = require('calendar.utils')
local M = {}

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
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, { "Calendar" })
    for _, d in ipairs(allData) do
        if d.type == "event" then
            vim.api.nvim_buf_set_lines(bufnr, -1, -1, true, {
                "Event: " .. d.title,
                "   Start: " .. utils.absoluteTimeToPretty(d.startTime),
                "   End: " .. utils.absoluteTimeToPretty(d.endTime),
                "   Description: " .. d.description,
                "   Location: " .. d.location,
                "",
            })
        else
            vim.api.nvim_buf_set_lines(bufnr, -1, -1, true, {
                "Assignment: " .. d.title,
                "   Due: " .. utils.absoluteTimeToPretty(d.due),
                "   Description: " .. d.description,
                "   Warning: " .. d.warnTime,
                "   Source: " .. (d.source or "None"),
                "",
            })
        end
    end
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, true, { "" })
    for _, d in ipairs(require('calendar').getRawData().jobs) do
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, true, {
            "Job: " .. d.id,
            "   Running: " .. (d.running and "Yes" or "No"),
            "   Next Run: " .. utils.absoluteTimeToPretty(d.nextRun),
        })
    end
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
end

function M.isRendering()
    return vim.api.nvim_get_current_buf() == bufnr
end

return M
