local blackboard = require("blackboard").singleton()
local request = require("util.scheduler").request
local action = require("action")

--- 下台阶任务。
---
--- 流程：
---  1. 正常导航到台阶入口
---  2. 切换到 StepController（保证最低速度 + 平滑末端速度）
---  3. 导航到台阶出口
---  4. 恢复 normal 控制器
---
--- @param forward_center boolean -- true = begin→final, false = final→begin
return function(forward_center)
	local user = blackboard.user
	local rule = blackboard.rule
	local condition = blackboard.condition

	local begin_ours = rule.one_step_begin.ours
	local begin_them = rule.one_step_begin.them
	local final_ours = rule.one_step_final.ours
	local final_them = rule.one_step_final.them

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

	action:update_controller("step")

	action:navigate(to)
	request:wait_until {
		monitor = function()
			return condition.near(to, 0.5)
		end,
		timeout = 15,
	}

	action:update_controller("normal")
	action:clear_target()
end
