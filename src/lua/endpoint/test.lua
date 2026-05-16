---
--- Test Endpoint: endpoint 负责顶层调度，intent 负责内部 phase-fsm。
---

local action = require("action")
local ascii = require("util.ascii_art")
local clock = require("util.clock")
local edge = require("util.edge")
local fsm = require("util.fsm")
local option = require("option")

local Scheduler = require("util.scheduler")
local scheduler = Scheduler.new()
local request = Scheduler.request

local intent_idle = require("intent.idle")
local intent_getout = require("intent.getout")
local intent_cruise = require("intent.cruise")
local intent_chase = require("intent.chase")
local intent_escape = require("intent.escape-to-home")

local edges = edge.new()

blackboard = require("blackboard").singleton()

local Endpoint = {
	idle = "idle",
	advance = "advance",
	combat = "combat",
	escape = "escape",
}

local Intent = {
	idle = "idle",
	getout = "getout",
	cruise = "cruise",
	chase = "chase",
	escape_to_home = "escape_to_home",
}

local intents = {}
local current_intent = nil
local combat_intent = Intent.cruise
local test_started = false

local function is_stage_started()
	return blackboard.game.stage == "STARTED"
end

local function clear_navigation_target()
	action:clear_target()
end

local function stop_all_behavior()
	clear_navigation_target()
	action:switch_navigation(false)
	action:update_enable_autoaim(false)
	action:update_gimbal_dominator("manual")
	action:update_chassis_mode("auto")
	blackboard.game.target_mode = 0
end

local function should_escape()
	return blackboard.condition.low_health()
		or blackboard.condition.low_bullet()
		or blackboard.game.base_health < blackboard.rule.base_health_red_line
end

local function recover_ready()
	return blackboard.condition.health_ready() and blackboard.condition.bullet_ready()
end

local function desired_combat_intent()
	if blackboard.user.auto_aim_should_control then
		return Intent.chase
	end
	return Intent.cruise
end

local function intent_phase(intent_id)
	local intent = intents[intent_id]
	if intent == nil or type(intent.phase) ~= "function" then
		return nil
	end
	return intent:phase()
end

local function activate_intent(intent_id)
	assert(intents[intent_id] ~= nil, "intent is not registered: " .. tostring(intent_id))
	if current_intent == intent_id then
		return
	end
	current_intent = intent_id
	intents[intent_id]:enter()
end

local function spin_active_intent()
	assert(current_intent ~= nil, "active intent is required")
	intents[current_intent]:spin_once()
	return intent_phase(current_intent)
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

local function append_revive_confirm_task()
	scheduler:append_task(function()
		while true do
			if blackboard.game.can_confirm_free_revive then
				action:confirm_revive()
			end
			request:yield()
		end
	end)
end

local function append_diagnostic_task(endpoint_fsm)
	scheduler:append_task(function()
		while true do
			request:sleep(1.0)
			action:info(string.format(
				"[TEST] endpoint=%s intent=%s phase=%s stage=%s started=%s hp=%d bullet=%d base=%d autoaim=%s",
				tostring(endpoint_fsm.details.current_state),
				tostring(current_intent),
				tostring(current_intent and intent_phase(current_intent) or "none"),
				blackboard.game.stage,
				tostring(test_started),
				blackboard.user.health,
				blackboard.user.bullet,
				blackboard.game.base_health,
				tostring(blackboard.user.auto_aim_should_control)
			))
		end
	end)
end

on_init = function()
	action:bind(scheduler)
	action:info(ascii.banner)
	action:warn("⚠️ TEST intent/phase 调度模式")

	clock:reset(blackboard.meta.timestamp)
	option:set_handler(function(error)
		action:fuck("while fetch option: " .. error)
	end)
	if option.enable_goal_topic_forward then
		action:switch_topic_forward(true)
	end

	intents = {
		[Intent.idle] = intent_idle.new(),
		[Intent.getout] = intent_getout.new(),
		[Intent.cruise] = intent_cruise.new(),
		[Intent.chase] = intent_chase.new(),
		[Intent.escape_to_home] = intent_escape.new(),
	}

	local endpoint_fsm = fsm:new(Endpoint.idle)

	endpoint_fsm:use {
		state = Endpoint.idle,
		enter = function()
			test_started = false
			combat_intent = Intent.cruise
			stop_all_behavior()
			activate_intent(Intent.idle)
		end,
		event = function(handle)
			spin_active_intent()
			if is_stage_started() then
				test_started = true
				handle:set_next(Endpoint.advance, "stage started")
				return
			end
			handle:set_next(Endpoint.idle)
		end,
		transitions = {
			{ to = Endpoint.advance, label = "stage started" },
		},
	}

	endpoint_fsm:use {
		state = Endpoint.advance,
		enter = function()
			activate_intent(Intent.getout)
		end,
		event = function(handle)
			if not is_stage_started() then
				handle:set_next(Endpoint.idle, "stage stopped")
				return
			end
			if should_escape() then
				handle:set_next(Endpoint.escape, "need recover")
				return
			end

			local phase = spin_active_intent()
			if phase == "done" then
				combat_intent = desired_combat_intent()
				handle:set_next(Endpoint.combat, "route ready")
				return
			end
			if phase == "failed" then
				handle:set_next(Endpoint.escape, "route failed")
				return
			end
			handle:set_next(Endpoint.advance)
		end,
		transitions = {
			{ to = Endpoint.idle, label = "stage stopped" },
			{ to = Endpoint.escape, label = "need recover" },
			{ to = Endpoint.escape, label = "route failed" },
			{ to = Endpoint.combat, label = "route ready" },
		},
	}

	endpoint_fsm:use {
		state = Endpoint.combat,
		enter = function()
			combat_intent = desired_combat_intent()
			activate_intent(combat_intent)
		end,
		event = function(handle)
			if not is_stage_started() then
				handle:set_next(Endpoint.idle, "stage stopped")
				return
			end
			if should_escape() then
				handle:set_next(Endpoint.escape, "need recover")
				return
			end

			local desired = desired_combat_intent()
			if desired ~= combat_intent then
				combat_intent = desired
				activate_intent(combat_intent)
			end

			local phase = spin_active_intent()
			if phase == "failed" then
				handle:set_next(Endpoint.escape, "combat failed")
				return
			end
			handle:set_next(Endpoint.combat)
		end,
		transitions = {
			{ to = Endpoint.idle, label = "stage stopped" },
			{ to = Endpoint.escape, label = "need recover" },
			{ to = Endpoint.escape, label = "combat failed" },
		},
	}

	endpoint_fsm:use {
		state = Endpoint.escape,
		enter = function()
			activate_intent(Intent.escape_to_home)
		end,
		event = function(handle)
			if not is_stage_started() then
				handle:set_next(Endpoint.idle, "stage stopped")
				return
			end

			spin_active_intent()
			if recover_ready() then
				combat_intent = desired_combat_intent()
				handle:set_next(Endpoint.combat, "recover ready")
				return
			end
			handle:set_next(Endpoint.escape)
		end,
		transitions = {
			{ to = Endpoint.idle, label = "stage stopped" },
			{ to = Endpoint.combat, label = "recover ready" },
		},
	}

	if not endpoint_fsm:init_ready(Endpoint) then
		error("test endpoint fsm not ready")
	end

	edges:on(blackboard.getter.rswitch, "UP", function()
		if endpoint_fsm.details.current_state ~= Endpoint.escape then
			action:warn("[TEST] 右拨杆 UP，强制进入撤退")
			endpoint_fsm:start_on(Endpoint.escape)
		end
	end)

	append_navigation_gate_task()
	append_mode_sync_task()
	append_revive_confirm_task()
	append_diagnostic_task(endpoint_fsm)

	scheduler:append_task(function()
		while true do
			endpoint_fsm:spin_once()
			request:yield()
		end
	end)
end

on_tick = function()
	clock:update(blackboard.meta.timestamp)
	edges:spin()
	scheduler:spin_once()
end

on_exit = function()
	stop_all_behavior()
	action:stop_navigation()
end
