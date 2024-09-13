local M = {}

---@param str string
---@return string
function M.strip(str)
    local i = 1
    while str:byte(i, i) <= 32 do
        i = i + 1
    end
    local e = #str
    while str:byte(e, e) <= 32 do
        e = e - 1
    end
    return str:sub(i, e)
end

---@param buf number
function M.parseBuf(buf)
    local line = 0
    local lineCount = #vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    while line < lineCount do
        local str = string.lower(vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1])
        line = line + 1

        local thing = {
            type = str,
            done = false,
            source = "manual"
        }

        if str ~= "assignment" and str ~= "event" then
            error("Expected assignment/event, got " .. str)
        end

        local spl = {}
        repeat
            spl = vim.split(vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1], ":")
            line = line + 1
            if #spl < 2 then
                break
            end
            local right = spl[2]
            local i = 3
            while i <= #spl do
                right = right .. ":" .. spl[i]
                i = i + 1
            end
            local left = M.strip(spl[1])
            right = M.strip(right)
            thing[left] = right
        until line >= lineCount

        if str == "assignment" then
            require('calendar').addAssignment(thing)
        else
            require('calendar').addEvent(thing)
        end
    end
end

return M
