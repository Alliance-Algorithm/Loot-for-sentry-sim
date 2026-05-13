local blackboard = require("blackboard").singleton()
local request = require("util.scheduler").request
local action = require("action")

--- 过起伏路段任务。
---
--- 流程：
---  1. 正常导航到入口
---  2. 切换到 RoadController + 云台沿路段方向
---  3. 直线导航到出口（控制器裁剪侧向分量，防卡路）
---  4. 恢复 normal 控制器 + 释放云台覆盖
---
--- @param forward_center boolean -- true = begin→final, false = final→begin
return function(forward_center)
	local user = blackboard.user
	local rule = blackboard.rule
	local condition = blackboard.condition

	local begin_ours = rule.rough_terrain_begin.ours
	local begin_them = rule.rough_terrain_begin.them
	local final_ours = rule.rough_terrain_final.ours
	local final_them = rule.rough_terrain_final.them

	local dist_ours = math.sqrt((user.x - begin_ours.x) ^ 2 + (user.y - begin_ours.y) ^ 2)
	local dist_them = math.sqrt((user.x - begin_them.x) ^ 2 + (user.y - begin_them.y) ^ 2)

	local begin, final
	if dist_ours <= dist_them then
		begin, final = begin_ours, final_ours
	else
		begin, final = begin_them, final_them
	end

	local from, to
	if forward_center then
		from, to = begin, final
	else
		from, to = final, begin
	end

	action:navigate(from)
	request:wait_until {
		monitor = function()
			return condition.near(from, 0.3)
		end,
		timeout = 10,
	}

	action:update_controller("road")
	local dx = to.x - from.x
	local dy = to.y - from.y
	action:update_gimbal_direction(math.atan(dy, dx))

	action:navigate(to)
	request:wait_until {
		monitor = function()
			return condition.near(to, 0.3)
		end,
		timeout = 25,
	}

	action:update_controller("normal")
	action:update_gimbal_direction(0 / 0)
	action:clear_target()
end
