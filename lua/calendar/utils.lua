local M = {}

---@param modules table<string, string>
function M.lazyRequire(modules)
	local loaded = {}
	return setmetatable({}, {
		__index = function(_, key)
			if not loaded[key] then
				loaded[key] = require(modules[key])
			end
			return loaded[key]
		end,
	})
end

---@return integer
function M.getSeconds()
	return os.time()
end

---@param str string A string that's in a format like 1h, 30m, 1h30m, 1h 30m, 1h 30m 30s
---@return integer
function M.lengthStrToDelta(str)
	local seconds = 0
	local tempStr = ""
	local mult = false
	if str:sub(1, 1) == "-" then
		mult = true
		str = str:sub(2)
	end
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
	if mult then
		seconds = seconds * -1
	end

	return seconds
end

---@param d integer
---@return string
function M.deltaToLengthStr(d)
	local ret = ""
	local units = {
		{ 86400, "d" },
		{ 3600, "h" },
		{ 60, "m" },
		{ 1, "s" },
	}
	if d < 0 then
		ret = "-"
		d = d * -1
	end
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
	return vim.fn.strptime(require("calendar").getOpts().dateFormat, str)
end

function M.absoluteTimeToPretty(str)
	str = M.absoluteTimeToSeconds(str)
	-- check if they are on the same day
	-- if they are, only show the time
	if os.date("%Y-%m-%d", str) == os.date("%Y-%m-%d", M.getSeconds()) then
		return "Today " .. os.date("%I:%M %p", str)
	end
	-- If they are before 1 week from now, show the day of the week
	if str < M.getSeconds() + 604800 then
		return os.date("%A, %I:%M %p", str)
	end
	return vim.fn.strftime(require("calendar").getOpts().dateFormat, str)
end

return M
