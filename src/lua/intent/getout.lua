--- 意图：出区（比赛开始后，按路径点导航到巡航区域）
---
--- 路径：road_zone_begin → way_point_1 → way_point_2 → road_zone_final
--- 全部到达后自动切换到 cruise。

local action = require("action")
local blackboard = require("blackboard").singleton()
local fsm = require("util.fsm")

local M = {}

local waypoints = nil
local index = 0
local TOLERANCE = 0.6
function M.enter()
	local rule = blackboard.rule
	waypoints = {
		rule.road_zone_begin.ours,
		rule.road_zone_way_point_0.ours,
		rule.road_zone_way_point_1.ours,
		rule.road_zone_way_point_2.ours,
		rule.road_zone_final.ours,
		rule.road_zone_final0.ours,
	}
	index = 1
	action:info(string.format("[GETOUT] 开始出区导航，共 %d 个路径点", #waypoints))
	action:navigate(waypoints[1])
	-- action:switch_mode(3)
end

function M.event(handle)
	local condition = blackboard.condition
	local wp = waypoints[index]

	if condition.near(wp, TOLERANCE) then
		action:info(string.format("[GETOUT] 到达路径点 %d/%d (%.1f, %.1f)", index, #waypoints, wp.x, wp.y))
		index = index + 1
		if index >= #waypoints then
			action:info("[GETOUT] 出区完成，进入巡航")
			handle:set_next("cruise")
			return
		end
		wp = waypoints[index]
		action:info(string.format("[GETOUT] 导航到路径点 %d/%d (%.1f, %.1f)", index, #waypoints, wp.x, wp.y))
		action:navigate(wp)
	else
		action:navigate(wp)
	end
	handle:set_next("getout")
end

function M.new()
	local driver = {
		phase_fsm = fsm:new("navigate"),
	}

	driver.phase_fsm:use {
		state = "navigate",
		event = function(handle)
			local condition = blackboard.condition
			local wp = waypoints[index]

			if wp == nil then
				handle:set_next("done")
				return
			end

			if condition.near(wp, TOLERANCE) then
				action:info(string.format("[GETOUT] 到达路径点 %d/%d (%.1f, %.1f)", index, #waypoints, wp.x, wp.y))
				index = index + 1
				if index >= #waypoints then
					action:info("[GETOUT] 出区完成，进入巡航")
					handle:set_next("done", "route finished")
					return
				end
				wp = waypoints[index]
				action:info(string.format("[GETOUT] 导航到路径点 %d/%d (%.1f, %.1f)", index, #waypoints, wp.x, wp.y))
				action:navigate(wp)
			else
				action:navigate(wp)
			end
			handle:set_next("navigate")
		end,
		transitions = {
			{ to = "done", label = "route finished" },
		},
	}

	driver.phase_fsm:use {
		state = "done",
		event = function(handle)
			handle:set_next("done")
		end,
	}

	function driver:enter()
		self.phase_fsm:start_on("navigate")
		M.enter()
	end

	function driver:spin_once()
		local before = index
		self.phase_fsm:spin_once()
		if before >= #waypoints and index >= #waypoints then
			self.phase_fsm:start_on("done")
		end
	end

	function driver:phase()
		if index >= #waypoints then
			return "done"
		end
		return self.phase_fsm.details.current_state
	end

	return driver
end

return M
