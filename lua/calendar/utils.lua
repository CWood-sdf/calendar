local M = {}

---@return integer
function M.getSeconds()
    return os.time()
end

---@param str string A string that's in a format like 1h, 30m, 1h30m, 1h 30m, 1h 30m 30s
---@return integer
function M.lengthStrToDelta(str)
    local seconds = 0
    local tempStr = ""
    for i = 1, #str do
        local char = str:sub(i, i)
        if char:match("%d") then
            tempStr = tempStr .. char
        elseif tempStr ~= "" then
            local unit = str:sub(i, i)
            if unit == "h" then
                seconds = seconds + (tonumber(tempStr) * 3600)
            elseif unit == "m" then
                seconds = seconds + (tonumber(tempStr) * 60)
            elseif unit == "s" then
                seconds = seconds + tonumber(tempStr)
            elseif unit == "d" then
                seconds = seconds + (tonumber(tempStr) * 86400)
            else
                error("Invalid unit: " .. unit)
            end
            tempStr = ""
        end
    end

    return seconds
end

---@param d integer
---@return string
function M.deltaToLengthStr(d)
    local ret = ""
    local units = {
        { 86400, "d" },
        { 3600,  "h" },
        { 60,    "m" },
        { 1,     "s" }
    }
    for _, unit in ipairs(units) do
        local unitDelta = math.floor(d / unit[1])
        if unitDelta > 0 then
            ret = ret .. unitDelta .. unit[2] .. " "
            d = d - (unitDelta * unit[1])
        end
        if d == 0 then
            break
        end
    end
    return ret
end

---@param str string|integer
function M.relativeTimeToSeconds(str)
    if type(str) ~= "string" then
        return str
    end
    return M.lengthStrToDelta(str)
end

function M.absoluteTimeToSeconds(str)
    if type(str) ~= "string" then
        return str
    end
    return vim.fn.strptime(require('calendar').getOpts().dateFormat, str)
end

function M.absoluteTimeToPretty(str)
    if type(str) == "string" then
        return str
    end
    return vim.fn.strftime(require('calendar').getOpts().dateFormat, str)
end

return M
