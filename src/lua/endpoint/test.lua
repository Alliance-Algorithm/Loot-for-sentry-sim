---
--- Test Endpoint: complete route / patrol / resupply / guard-home flow
---

local action = require("action")
local ascii = require("util.ascii_art")
local clock = require("util.clock")
local fsm = require("util.fsm")
local option = require("option")

local Scheduler = require("util.scheduler")
local scheduler = Scheduler.new()
local request = Scheduler.request

blackboard = require("blackboard").singleton()
local NaN = 0 / 0

local Intent = {
	idle = "idle",
	cross_road_zone = "cross_road_zone",
	cross_rough_terrain = "cross_rough_terrain",
	climb_to_highland = "climb_to_highland",
	patrol_highland = "patrol_highland",
	return_by_one_step = "return_by_one_step",
	resupply = "resupply",
	guard_fortress = "guard_fortress",
}

local resume_target = Intent.patrol_highland
local patrol_index = 1
local test_started = false

local function is_stage_started()
	return blackboard.game.stage == "STARTED"
end

local function clear_navigation_target()
	action.target.x = NaN
	action.target.y = NaN
end

local function stop_all_behavior()
	clear_navigation_target()
	action:switch_navigation(false)
	action:update_enable_autoaim(false)
	action:update_gimbal_dominator("manual")
	action:update_chassis_mode("auto")
	blackboard.game.target_mode = 0
end

local function near(point, tolerance)
	return blackboard.condition.near(point, tolerance)
end

local function navigate_and_wait(point, tolerance, timeout)
	action:navigate(point)
	request:wait_until {
		monitor = function()
			return near(point, tolerance) or not is_stage_started()
		end,
		timeout = timeout,
	}
	return is_stage_started() and near(point, tolerance)
end

local function stage_sleep(seconds)
	request:wait_until {
		monitor = function()
			return not is_stage_started()
		end,
		timeout = seconds,
	}
	return is_stage_started()
end

local function switch_combat_pose(enable_spin)
	if enable_spin then
		action:update_chassis_mode("spin")
	else
		action:update_chassis_mode("auto")
	end
	action:update_enable_autoaim(false)
end

local function enter_navigation_pose()
	action:update_chassis_mode("auto")
	action:update_enable_autoaim(false)
end

local function should_guard_home()
	return blackboard.game.base_health < blackboard.rule.base_health_red_line
end

local function should_resupply()
	return blackboard.condition.low_health() or blackboard.condition.low_bullet()
end

local function resupply_ready()
	return blackboard.condition.health_ready() and blackboard.condition.bullet_ready()
end

local function current_patrol_target()
	local rule = blackboard.rule
	local targets = { rule.center_highland_point1, rule.center_highland_point2 }
	return targets[patrol_index], targets
end

local function set_patrol_next()
	patrol_index = patrol_index % 2 + 1
end

local function choose_resume_from_emergency()
	if should_guard_home() then
		return Intent.guard_fortress
	end
	return Intent.resupply
end

local function append_stage_start_task(intent_fsm)
	scheduler:append_task(function()
		while true do
			if not test_started and is_stage_started() then
				action:info("[TEST] stage STARTED, begin route with Godot navigation")
				test_started = true
				resume_target = Intent.patrol_highland
				patrol_index = 1
				intent_fsm:start_on(Intent.cross_road_zone)
			end
			request:yield()
		end
	end)
end

local function append_navigation_gate_task()
	scheduler:append_task(function()
		while true do
			action:switch_navigation(test_started and is_stage_started())
			request:yield()
		end
	end)
end

local function append_mode_sync_task()
	scheduler:append_task(function()
		while true do
			if is_stage_started() then
				local current = blackboard.game.sentry_mode
				local target = blackboard.game.target_mode
				if target ~= 0 and current ~= target then
					action:switch_mode(target)
				end
			end
			request:yield()
		end
	end)
end

local function append_diagnostic_task(intent_fsm)
	scheduler:append_task(function()
		while true do
			request:sleep(1.0)
			action:info(string.format(
				"[TEST] state=%s stage=%s started=%s hp=%d bullet=%d base=%d target_mode=%d autoaim=%s",
				intent_fsm.details.current_state,
				blackboard.game.stage,
				tostring(test_started),
				blackboard.user.health,
				blackboard.user.bullet,
				blackboard.game.base_health,
				blackboard.game.target_mode,
				tostring(blackboard.user.auto_aim_should_control)
			))
		end
	end)
end

on_init = function()
	action:bind(scheduler)
	action:info(ascii.banner)
	action:warn("⚠️ TEST 完整流程模式")

	clock:reset(blackboard.meta.timestamp)
	option:set_handler(function(error)
		action:fuck("while fetch option: " .. error)
	end)
	if option.enable_goal_topic_forward then
		action:switch_topic_forward(true)
	end

	local intent_fsm = fsm:new(Intent.idle)

	intent_fsm:use {
		state = Intent.idle,
		enter = function()
			action:info("[TEST] waiting for game stage STARTED")
			stop_all_behavior()
		end,
		event = function(handle)
			handle:set_next(Intent.idle)
		end,
	}

	intent_fsm:use {
		state = Intent.cross_road_zone,
		enter = function()
			enter_navigation_pose()
			blackboard.game.target_mode = 2
			local rule = blackboard.rule
			local route = {
				rule.road_zone_begin.ours,
				rule.road_zone_way_point_0.ours,
				rule.road_zone_way_point_1.ours,
				rule.road_zone_way_point_2.ours,
				rule.road_zone_final.ours,
			}
			for _, point in ipairs(route) do
				if not navigate_and_wait(point, 0.4, 15.0) then
					return
				end
			end
		end,
		event = function(handle)
			if not is_stage_started() then
				handle:set_next(Intent.idle)
				return
			end
			if should_guard_home() then
				resume_target = Intent.guard_fortress
				handle:set_next(Intent.guard_fortress)
				return
			end
			if should_resupply() then
				resume_target = Intent.resupply
				handle:set_next(Intent.resupply)
				return
			end
			handle:set_next(Intent.cross_rough_terrain)
		end,
	}

	intent_fsm:use {
		state = Intent.cross_rough_terrain,
		enter = function()
			enter_navigation_pose()
			blackboard.game.target_mode = 2
			local rule = blackboard.rule
			if not navigate_and_wait(rule.rough_terrain_begin.ours, 0.4, 15.0) then
				return
			end
			if not navigate_and_wait(rule.rough_terrain_final.ours, 0.5, 25.0) then
				return
			end
		end,
		event = function(handle)
			if not is_stage_started() then
				handle:set_next(Intent.idle)
				return
			end
			if should_guard_home() then
				resume_target = Intent.guard_fortress
				handle:set_next(Intent.guard_fortress)
				return
			end
			if should_resupply() then
				resume_target = Intent.resupply
				handle:set_next(Intent.resupply)
				return
			end
			handle:set_next(Intent.climb_to_highland)
		end,
	}

	intent_fsm:use {
		state = Intent.climb_to_highland,
		enter = function()
			enter_navigation_pose()
			blackboard.game.target_mode = 2
			local point, _ = current_patrol_target()
			if not navigate_and_wait(point, 0.4, 20.0) then
				return
			end
		end,
		event = function(handle)
			if not is_stage_started() then
				handle:set_next(Intent.idle)
				return
			end
			handle:set_next(Intent.patrol_highland)
		end,
	}

	intent_fsm:use {
		state = Intent.patrol_highland,
		enter = function()
			switch_combat_pose(true)
			blackboard.game.target_mode = 2
		end,
		event = function(handle)
			if not is_stage_started() then
				handle:set_next(Intent.idle)
				return
			end
			if should_guard_home() then
				resume_target = Intent.guard_fortress
				handle:set_next(Intent.return_by_one_step)
				return
			end
			if should_resupply() then
				resume_target = Intent.resupply
				handle:set_next(Intent.return_by_one_step)
				return
			end

			local point, _ = current_patrol_target()
			action:navigate(point)
			if near(point, 0.35) then
				if not stage_sleep(1.0) then
					handle:set_next(Intent.idle)
					return
				end
				set_patrol_next()
			else
				if not stage_sleep(0.1) then
					handle:set_next(Intent.idle)
					return
				end
			end
			handle:set_next(Intent.patrol_highland)
		end,
	}

	intent_fsm:use {
		state = Intent.return_by_one_step,
		enter = function()
			enter_navigation_pose()
			blackboard.game.target_mode = 2
			local rule = blackboard.rule
			if not navigate_and_wait(rule.one_step_begin.ours, 0.4, 15.0) then
				return
			end
			if not navigate_and_wait(rule.one_step_final.ours, 0.5, 20.0) then
				return
			end
		end,
		event = function(handle)
			if not is_stage_started() then
				handle:set_next(Intent.idle)
				return
			end
			handle:set_next(resume_target)
		end,
	}

	intent_fsm:use {
		state = Intent.resupply,
		enter = function()
			enter_navigation_pose()
			blackboard.game.target_mode = 2
			if not navigate_and_wait(blackboard.rule.resupply_zone.ours, 0.4, 20.0) then
				return
			end
			switch_combat_pose(true)
		end,
		event = function(handle)
			if not is_stage_started() then
				handle:set_next(Intent.idle)
				return
			end
			if should_guard_home() then
				resume_target = Intent.guard_fortress
				handle:set_next(Intent.guard_fortress)
				return
			end
			if resupply_ready() then
				resume_target = Intent.patrol_highland
				handle:set_next(Intent.climb_to_highland)
				return
			end
			if not stage_sleep(0.2) then
				handle:set_next(Intent.idle)
				return
			end
			handle:set_next(Intent.resupply)
		end,
	}

	intent_fsm:use {
		state = Intent.guard_fortress,
		enter = function()
			enter_navigation_pose()
			blackboard.game.target_mode = 2
			if not navigate_and_wait(blackboard.rule.fortress.ours, 0.4, 20.0) then
				return
			end
			switch_combat_pose(true)
		end,
		event = function(handle)
			if not is_stage_started() then
				handle:set_next(Intent.idle)
				return
			end
			if blackboard.game.base_health >= blackboard.rule.base_health_red_line then
				if should_resupply() then
					resume_target = Intent.resupply
					handle:set_next(Intent.resupply)
				else
					resume_target = Intent.patrol_highland
					handle:set_next(Intent.climb_to_highland)
				end
				return
			end
			if not stage_sleep(0.2) then
				handle:set_next(Intent.idle)
				return
			end
			handle:set_next(Intent.guard_fortress)
		end,
	}

	if not intent_fsm:init_ready(Intent) then
		error("test intent fsm not ready")
	end

	append_stage_start_task(intent_fsm)
	append_navigation_gate_task()
	append_mode_sync_task()
	append_diagnostic_task(intent_fsm)

	scheduler:append_task(function()
		while true do
			if not is_stage_started() then
				if test_started then
					action:info("[TEST] stage left STARTED, freeze robot")
					test_started = false
					resume_target = Intent.patrol_highland
					patrol_index = 1
					intent_fsm:start_on(Intent.idle)
				end
			elseif test_started then
				if should_guard_home() and intent_fsm.details.current_state ~= Intent.guard_fortress then
					resume_target = Intent.guard_fortress
					if intent_fsm.details.current_state == Intent.patrol_highland then
						intent_fsm:start_on(Intent.return_by_one_step)
					else
						intent_fsm:start_on(Intent.guard_fortress)
					end
				elseif should_resupply()
					and intent_fsm.details.current_state ~= Intent.resupply
					and intent_fsm.details.current_state ~= Intent.guard_fortress then
					resume_target = choose_resume_from_emergency()
					if intent_fsm.details.current_state == Intent.patrol_highland then
						intent_fsm:start_on(Intent.return_by_one_step)
					else
						intent_fsm:start_on(Intent.resupply)
					end
				end
			end

			intent_fsm:spin_once()
			request:yield()
		end
	end)
end

on_tick = function()
	clock:update(blackboard.meta.timestamp)
	scheduler:spin_once()
end

on_exit = function()
	action:stop_navigation()
end
