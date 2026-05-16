--- 意图：巡航（默认战斗意图）
---
--- 在 center_highland_point1 和 center_highland_point2 之间巡逻。
--- 持续控制云台以 ~1 rad/s 旋转，并开启自动瞄准。

local Scheduler = require("util.scheduler")
local scheduler = Scheduler.new()
local request = Scheduler.request
local fsm = require("util.fsm")

local action = require("action")
local blackboard = require("blackboard").singleton()
local M = {}

local patrol_points = nil
local current_target = 1
local gimbal_lead = 3.0 -- 目标角速度 1.0 rad/s 对应的超前角 (kp=0.5 时 = 1.0/0.5)

function M.enter()
	local rule = blackboard.rule
	patrol_points = { rule.center_highland_point1, rule.center_highland_point2 }
	current_target = 1

	action:info("[CRUISE] 进入巡航巡逻模式")
	action:update_chassis_mode("spin")
	action:update_enable_autoaim(true)
	action:navigate(patrol_points[current_target])
	-- action:switch_mode(2)
	blackboard.game.target_mode = 2
	request:sleep(4)
end

function M.event(handle)
	local condition = blackboard.condition
	-- action:switch_mode(2)
	blackboard.game.target_mode = 2
	local wp = patrol_points[current_target]
	if condition.near(wp, 0.3) then
		-- action:info(string.format("[CRUISE] 到达巡逻点 #%d (%.1f, %.1f)", current_target, wp.x, wp.y))
		request:sleep(1)
		current_target = current_target % #patrol_points + 1

		-- action:navigate(patrol_points[current_target])
	else
		-- action:navigate(wp)
		request:sleep(1)
	end

	-- action:update_gimbal_direction(blackboard.user.yaw + gimbal_lead)

	handle:set_next("cruise")
	-- action:switch_mode(2)
	blackboard.game.target_mode = 2
end

function M.new()
	local driver = {
		phase_fsm = fsm:new("patrol"),
	}

	driver.phase_fsm:use {
		state = "patrol",
		event = function(handle)
			local condition = blackboard.condition
			blackboard.game.target_mode = 2
			local wp = patrol_points[current_target]
			if condition.near(wp, 0.3) then
				request:sleep(1)
				current_target = current_target % #patrol_points + 1
			else
				request:sleep(1)
			end
			handle:set_next("patrol")
		end,
	}

	function driver:enter()
		self.phase_fsm:start_on("patrol")
		M.enter()
	end

	function driver:spin_once()
		self.phase_fsm:spin_once()
	end

	function driver:phase()
		return self.phase_fsm.details.current_state
	end

	return driver
end

return M
