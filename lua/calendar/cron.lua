---@class (exact) Calendar.Cron.ExpressionComponent
---@field value number
---@field isStar boolean
---@field every number
---@field rangeStart? number
---@field rangeEnd? number

---@class (exact) Calendar.Cron
---@field minute  Calendar.Cron.ExpressionComponent
---@field hour    Calendar.Cron.ExpressionComponent
---@field day     Calendar.Cron.ExpressionComponent
---@field month   Calendar.Cron.ExpressionComponent
---@field year    Calendar.Cron.ExpressionComponent
---@field dayOfWeek Calendar.Cron.DayOfWeek[]

local M = {}

---@enum Calendar.Cron.DayOfWeek
M.DayOfWeek = {
	Sunday = "SUN",
	Monday = "MON",
	Tuesday = "TUE",
	Wednesday = "WED",
	Thursday = "THU",
	Friday = "FRI",
	Saturday = "SAT",
}

local allDays = {
	M.DayOfWeek.Sunday,
	M.DayOfWeek.Monday,
	M.DayOfWeek.Tuesday,
	M.DayOfWeek.Wednesday,
	M.DayOfWeek.Thursday,
	M.DayOfWeek.Friday,
	M.DayOfWeek.Saturday,
}
---@return Calendar.Cron
function M:new()
	---@type Calendar.Cron
	local o = {
		minute = { value = 0, isStar = true, every = 1 },
		hour = { value = 0, isStar = true, every = 1 },
		day = { value = 1, isStar = true, every = 1 },
		month = { value = 1, isStar = true, every = 1 },
		year = { value = 1970, isStar = true, every = 1 },
		dayOfWeek = allDays,
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

---@param str string
---@return Calendar.Cron?
function M.parse(str)
	local cron = M:new()
	local parts = vim.split(str, " ")
	if #parts ~= 6 then
		error("Invalid cron expression, needs 6 parts separated by spaces: " .. str)
	end
	cron.minute = M.parseExpression(parts[1])
	cron.hour = M.parseExpression(parts[2])
	cron.day = M.parseExpression(parts[3])
	cron.month = M.parseExpression(parts[4])
	cron.year = M.parseExpression(parts[5])
	cron.dayOfWeek = M.parseDayOfWeek(parts[6])
	return cron
end

---@param str string
---@return Calendar.Cron.DayOfWeek[]
function M.parseDayOfWeek(str)
	if str == "*" then
		return allDays
	end
	local days = vim.split(str, ",")
	local ret = {}
	for _, day in ipairs(days) do
		local d = M.DayOfWeek[day:upper()]
		if d then
			table.insert(ret, d)
		else
			for _, v in ipairs(allDays) do
				if v:sub(1, #day):upper() == day:upper() then
					table.insert(ret, v)
				end
			end
		end
	end
	return ret
end

---@param component Calendar.Cron.ExpressionComponent
function M.getValidTime(component, min)
	if component.isStar then
		return min
	end
	if component.rangeStart then
		return component.rangeStart
	end
	if component.rangeEnd then
		return component.rangeEnd
	end
	return component.value
end

---@param component Calendar.Cron.ExpressionComponent
---@param max number
---@param val number
---@return number
---Turns a (possibly invalid) expression value into a valid one
function M.forceValidTime(component, max, val)
	if component.isStar then
		local every = component.every
		local ret = val - (val % every)
		return ret
	end
	if component.rangeStart and val < component.rangeStart then
		return component.rangeStart
	end
	if component.rangeEnd and val > component.rangeEnd then
		return component.rangeEnd
	end
	return val
end

---@param component Calendar.Cron.ExpressionComponent
---@param max number
---@param last number
---@return number, boolean -- The boolean is for overflow
function M.getNextValidTime(component, max, last)
	if component.isStar then
		local next = last + component.every
		if next > max then
			return 0, true
		end
		return next, false
	end
	if component.rangeStart ~= nil then
		local next = last + component.every
		if next > component.rangeEnd or next > max then
			return component.rangeStart, true
		end
		return next, false
	end
	return component.value, true -- Return true bc there can only be one value
end

---@return number
---@param self Calendar.Cron
function M.nextOccurence(self)
	local now = os.time()
	local year = M.forceValidTime(self.year, 9999, tonumber(os.date("%Y", now)) or 0)
	local month = M.forceValidTime(self.month, 12, tonumber(os.date("%m", now)) or 0)
	local day = M.forceValidTime(self.day, 31, tonumber(os.date("%d", now)) or 0)
	local hour = M.forceValidTime(self.hour, 23, tonumber(os.date("%H", now)) or 0)
	local min = M.forceValidTime(self.minute, 59, tonumber(os.date("%M", now)) or 0)
	local nextTime = os.time({
		year = year,
		month = month,
		day = day,
		hour = hour,
		min = min,
		sec = 0,
	})
	local currentTime = {
		year = os.date("%Y", nextTime),
		month = os.date("%m", nextTime),
		day = os.date("%d", nextTime),
		hour = os.date("%H", nextTime),
		min = os.date("%M", nextTime),
		sec = 0,
	}
	local arr = { self.minute, self.hour, self.day, self.month, self.year }
	local formats = { "%M", "%H", "%d", "%m", "%Y" }
	local max = { 59, 23, 31, 12, 9999 }
	local names = { "min", "hour", "day", "month", "year" }
	local exit = false
	local maxIters = 100000000
	while not exit do
		local overflow = false
		local i = 1
		local next = 0
		repeat
			-- local d = os.date(formats[i], nextTime)
			---@type number
			local lastComponentValue = tonumber(os.date(formats[i], nextTime)) or 0
			next, overflow = M.getNextValidTime(arr[i], max[i], lastComponentValue)
			currentTime[names[i]] = next
			i = i + 1
		until not overflow
		i = i - 1
		nextTime = os.time(currentTime)
		exit = nextTime > now
		if not vim.tbl_contains(self.dayOfWeek, os.date("%a", nextTime):upper()) then
			exit = false
		end
		maxIters = maxIters - 1
		if maxIters < 0 then
			return nextTime
		end
	end
	-- print(vim.inspect(self.dayOfWeek))
	-- print(os.date("%a", nextTime):upper())
	return nextTime
end

---@param str string
---@return Calendar.Cron.ExpressionComponent
function M.parseExpression(str)
	---@type Calendar.Cron.ExpressionComponent
	local component = { value = 0, isStar = false, every = 1 }
	local parts = vim.split(str, "/")
	if #parts == 2 then
		component.every = tonumber(parts[2]) or 1
		str = parts[1]
	end
	if str == "*" then
		component.isStar = true
		-- return component
	end
	local range = vim.split(str, "-")
	if #range == 2 then
		component.rangeStart = tonumber(range[1])
		component.rangeEnd = tonumber(range[2])
		component.every = component.every or 1
	else
		component.value = tonumber(str) or 0
	end
	return component
end

return M
