local validate = {}
function validate.validateAbsoluteTime(time)
	if type(time) == "string" then
		return ""
	end
	if type(time) == "number" then
		return ""
	end
	return "Time must be a string or a number"
end

function validate.validateRelativeTime(time)
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
function validate.event(e)
	if type(e.title) ~= "string" then
		return "Title must be a string"
	end
	if type(e.description) ~= "string" then
		return "Description must be a string"
	end

	local validateStart = validate.validateAbsoluteTime(e.startTime)
	if validateStart ~= "" then
		return "Start " .. validateStart
	end

	local validateEnd = validate.validateAbsoluteTime(e.endTime)
	if validateEnd ~= "" then
		return "End " .. validateEnd
	end

	local validateWarn = validate.validateRelativeTime(e.warnTime)
	if validateWarn ~= "" then
		return "Warn " .. validateWarn
	end

	if type(e.location) ~= "string" then
		return "Location must be a string"
	end

	if type(e.type) ~= "string" then
		return "Type must be a string"
	end
	if e.type ~= "event" then
		return "Type must be 'event'"
	end
	return ""
end

---@param a CalendarAssignment
---@return string
function validate.assignment(a)
	if type(a.title) ~= "string" then
		return "Title must be a string"
	end
	if type(a.description) ~= "string" then
		return "Description must be a string"
	end
	local validateDue = validate.validateAbsoluteTime(a.due)
	if validateDue ~= "" then
		return "Due " .. validateDue
	end
	local validateWarn = validate.validateRelativeTime(a.warnTime)
	if validateWarn ~= "" then
		return "Warn " .. validateWarn
	end
	if type(a.type) ~= "string" then
		return "Type must be a string"
	end
	if a.type ~= "assignment" then
		return "Type must be 'assignment'"
	end
	return ""
end
return validate
