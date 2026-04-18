local option = {}

--- @type nil | fun(error: string)
local missing_handler = nil

--- Register a handler for missing option access.
--- @param handler fun(error: string)
--- @return nil
function option:set_handler(handler)
	missing_handler = handler
end

--- List all configured non-function options.
--- @return string
function option:list_all()
	local names = {}
	for name, value in pairs(self) do
		if string.find(name, "^qos_overrides") then
			goto continue
		end
		if type(value) ~= "function" then
			names[#names + 1] = string.format("  - %s: %s", name, tostring(value))
		end
		::continue::
	end

	return table.concat(names, "\n")
end

return setmetatable(option, {
	__index = function(_, key)
		if missing_handler then
			missing_handler(string.format("option '%s' not found", tostring(key)))
		end
		return nil
	end,
})
