local NaN = 0 / 0

local action = {
	target = {
		x = NaN,
		y = NaN,
	},
}

--- @param position {x: number, y: number}
function action:set_target(position)
	local x = position.x
	local y = position.y
	if x ~= x or y ~= y then
		return
	end

	self.target = position
end

return action
