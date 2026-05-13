--- 意图：巡航（默认战斗意图）
---
--- 在 center_highland_point1 和 center_highland_point2 之间巡逻。
--- 持续控制云台以 ~1 rad/s 旋转，并开启自动瞄准。

local Scheduler = require("util.scheduler")
local scheduler = Scheduler.new()
local request = Scheduler.request

local action = require("action")
local blackboard = require("blackboard").singleton()
local M = {}

local patrol_points = nil
local current_target = 1
local gimbal_lead = 2.5 -- 目标角速度 1.0 rad/s 对应的超前角 (kp=0.5 时 = 1.0/0.5)

function M.enter()
	local rule = blackboard.rule
	patrol_points = { rule.center_highland_point1, rule.center_highland_point2 }
	current_target = 1

	action:info("[CRUISE] 进入巡航巡逻模式")
	action:update_chassis_mode("spin")
	action:update_enable_autoaim(true)
	action:navigate(patrol_points[current_target])
end

function M.event(handle)
	local condition = blackboard.condition

	local wp = patrol_points[current_target]
	if condition.near(wp, 0.3) then
		action:info(string.format("[CRUISE] 到达巡逻点 #%d (%.1f, %.1f)", current_target, wp.x, wp.y))
		request:sleep(1)
		current_target = current_target % #patrol_points + 1

		action:navigate(patrol_points[current_target])
	else
		action:navigate(wp)
		request:sleep(1)
	end

	action:update_gimbal_direction(blackboard.user.yaw + gimbal_lead)

	handle:set_next("cruise")
end

return M
