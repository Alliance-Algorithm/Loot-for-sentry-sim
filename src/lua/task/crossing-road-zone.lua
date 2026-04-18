local blackboard = require("blackboard").singleton()
local request = require("util.scheduler").request
local action = require("action")

--- @param ours_zone boolean
--- @param forward_center boolean
return function(ours_zone, forward_center)
	local x = blackboard.user.x
	local y = blackboard.user.y

	local rule = blackboard.rule
	local begin, final
	if ours_zone then
		begin = rule.road_zone_begin.ours
		final = rule.road_zone_final.ours
	else
		begin = rule.road_zone_begin.them
		final = rule.road_zone_final.them
	end

	local from, to
	if forward_center then
		from = begin
		to = final
	else
		from = final
		to = begin
	end

	local condition = blackboard.condition

	action:navigate(from)
	local timeout = request:wait_until {
		monitor = function()
			return condition.near(from, 0.1)
		end,
		timeout = 10,
	}
end
