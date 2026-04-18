local M = {}

--- Return true if any argument is NaN.
--- @param ... any
--- @return boolean
function M.check_nan(...)
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		if type(value) == "number" and value ~= value then
			return true
		end
	end
	return false
end

return M
