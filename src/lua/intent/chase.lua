--- 意图：追击
---
--- 自瞄锁定目标时从巡航切换进入，由自瞄接管云台控制。
--- 导航锁定到当前位置原地待命，不主动控制云台方向。

local Scheduler = require("util.scheduler")
local scheduler = Scheduler.new()
local request = Scheduler.request

local action = require("action")
local blackboard = require("blackboard").singleton()

local M = {}

local patrol_points = nil
local current_target = 1

function M.enter()
	local rule = blackboard.rule
	patrol_points = { rule.center_highland_point1, rule.center_highland_point2 }
	current_target = 1

	action:info("[CHASE] 进入追击模式，自瞄接管云台")
	action:update_chassis_mode("spin")
	action:update_enable_autoaim(true)
	-- action:switch_mode(3)
	blackboard.game.target_mode = 1

	-- 导航到当前位置，覆盖巡航目标，让机器人原地待命
	local user = blackboard.user
	-- action:navigate({ x = user.x, y = user.y })
end

function M.event(handle)
	request:sleep(3)
	handle:set_next("chase")
	-- action:switch_mode(3)
	blackboard.game.target_mode = 1
end

return M
