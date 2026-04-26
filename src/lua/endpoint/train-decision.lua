---
--- Local Context
---

local action = require("action")
local ascii = require("util.ascii_art")
local clock = require("util.clock")
local fsm = require("util.fsm")
local option = require("option")

local start_cruise = require("intent.start-cruise-train")
local keep_cruise = require("intent.keep-cruise")
local escape_to_home = require("intent.escape-to-home")

local Scheduler = require("util.scheduler")
local scheduler = Scheduler.new()
local request = Scheduler.request

---
--- Export Context
---

blackboard = require("blackboard").singleton()

local runtime = {
	ours_zone = true,
	switch_interval = 2.0,
	current_state = "idle",
	navigation_ready = false,
}

local requests = {
	start = false,
}

local job = {
	handle = nil,
	name = nil,
	done = false,
	success = false,
}

local function read_option(name, fallback)
	local value = rawget(option, name)
	if value == nil then
		return fallback
	end
	return value
end

local function ensure_point_pair(rule, name)
	if type(rule[name]) ~= "table" then
		rule[name] = {
			ours = { x = 0.0, y = 0.0 },
			them = { x = 0.0, y = 0.0 },
		}
		return
	end

	if type(rule[name].ours) ~= "table" then
		rule[name].ours = { x = 0.0, y = 0.0 }
	end
	if type(rule[name].them) ~= "table" then
		rule[name].them = { x = 0.0, y = 0.0 }
	end

	rule[name].ours.x = tonumber(rule[name].ours.x) or 0.0
	rule[name].ours.y = tonumber(rule[name].ours.y) or 0.0
	rule[name].them.x = tonumber(rule[name].them.x) or 0.0
	rule[name].them.y = tonumber(rule[name].them.y) or 0.0
end

local function ensure_schema()
	if type(blackboard.user) ~= "table" then
		blackboard.user = {}
	end
	if type(blackboard.game) ~= "table" then
		blackboard.game = {}
	end
	if type(blackboard.play) ~= "table" then
		blackboard.play = {}
	end
	if type(blackboard.meta) ~= "table" then
		blackboard.meta = {}
	end
	if type(blackboard.result) ~= "table" then
		blackboard.result = {}
	end
	if type(blackboard.rule) ~= "table" then
		blackboard.rule = {}
	end

	blackboard.user.health = tonumber(blackboard.user.health) or 0
	blackboard.user.bullet = tonumber(blackboard.user.bullet) or 0
	blackboard.user.chassis_power_limit = tonumber(blackboard.user.chassis_power_limit) or 0
	blackboard.user.x = tonumber(blackboard.user.x) or 0
	blackboard.user.y = tonumber(blackboard.user.y) or 0
	blackboard.user.yaw = tonumber(blackboard.user.yaw) or 0

	blackboard.game.stage = tostring(blackboard.game.stage or "UNKNOWN")
	blackboard.play.rswitch = tostring(blackboard.play.rswitch or "UNKNOWN")
	blackboard.play.lswitch = tostring(blackboard.play.lswitch or "UNKNOWN")
	blackboard.meta.timestamp = tonumber(blackboard.meta.timestamp) or 0

	if type(blackboard.meta.navigate_point_queue) ~= "table" then
		blackboard.meta.navigate_point_queue = {}
	end

	local rule = blackboard.rule
	rule.health_limit = tonumber(rule.health_limit) or 0
	rule.health_ready = tonumber(rule.health_ready) or 0
	rule.bullet_limit = tonumber(rule.bullet_limit) or 0
	rule.bullet_ready = tonumber(rule.bullet_ready) or 0

	ensure_point_pair(rule, "resupply_zone")
	ensure_point_pair(rule, "road_zone_begin")
	ensure_point_pair(rule, "road_zone_final")
	ensure_point_pair(rule, "one_step_begin")
	ensure_point_pair(rule, "one_step_final")
	ensure_point_pair(rule, "fluctuant_road_begin")
	ensure_point_pair(rule, "fluctuant_road_final")
	ensure_point_pair(rule, "central_highland_near_crossing_road")
	ensure_point_pair(rule, "central_highland_near_doghole")

	if type(blackboard.enqueue_navigate_point) ~= "function" then
		blackboard.enqueue_navigate_point = function(point, source)
			if type(point) ~= "table" then
				return
			end
			if type(point.x) ~= "number" or type(point.y) ~= "number" then
				return
			end

			local queue = blackboard.meta.navigate_point_queue
			if type(queue) ~= "table" then
				queue = {}
				blackboard.meta.navigate_point_queue = queue
			end

			queue[#queue + 1] = {
				x = point.x,
				y = point.y,
				source = source or "unknown",
				timestamp = blackboard.meta.timestamp,
			}

			local max_history = 64
			while #queue > max_history do
				table.remove(queue, 1)
			end
		end
	end
end

local function set_reason(reason)
	if type(blackboard.result) ~= "table" then
		blackboard.result = {}
	end
	blackboard.result.last_reason = tostring(reason or "")
end

local function publish_decision_state(progress)
	if type(blackboard.result) ~= "table" then
		blackboard.result = {}
	end
	if type(blackboard.meta) ~= "table" then
		blackboard.meta = {}
	end

	blackboard.meta.fsm_state = runtime.current_state
	blackboard.result.intent = runtime.current_state
	blackboard.result.task = job.name or "idle"
	blackboard.result.job_done = job.done
	blackboard.result.job_success = job.success
	blackboard.result.progress = progress or blackboard.result.progress or "running"
end

local function configure_test_rule()
	local rule = blackboard.rule

	rule.health_limit = read_option("fsm_health_limit", 200)
	rule.health_ready = read_option("fsm_health_ready", 400)
	rule.bullet_limit = read_option("fsm_bullet_limit", 30)
	rule.bullet_ready = read_option("fsm_bullet_ready", 300)

	-- Ours side sample points
	rule.resupply_zone.ours = { x = -1.2, y = 6.0 }
	rule.road_zone_begin.ours = { x = 1.5, y = 4.4 }
	rule.road_zone_final.ours = { x = 6.5, y = 6.5 }
	rule.fluctuant_road_begin.ours = { x = 2.5, y = 6.5 }
	rule.fluctuant_road_final.ours = { x = 5.5, y = 6.5 }
	rule.one_step_begin.ours = { x = 4.4, y = 6.2 }
	rule.one_step_final.ours = { x = 4.4, y = 4.6 }
	rule.central_highland_near_crossing_road.ours = { x = 8.8, y = 4.0 }
	rule.central_highland_near_doghole.ours = { x = 10.5, y = -4.0 }
end

local function reset_job_status()
	job.done = false
	job.success = false
end

local function cancel_job()
	if job.handle ~= nil then
		job.handle.cancel()
		job.handle = nil
	end
	job.name = nil
	reset_job_status()
	publish_decision_state("job_canceled")
end

local function run_job(name, fn)
	cancel_job()
	job.name = name
	reset_job_status()
	publish_decision_state("job_running")

	job.handle = scheduler:append_task(function()
		local ok, result = xpcall(fn, debug.traceback)
		job.handle = nil
		job.name = nil
		job.done = true

		if not ok then
			job.success = false
			publish_decision_state("job_failed")
			action:fuck(string.format("fsm job '%s' failed:\n%s", name, result))
			return
		end

		job.success = (result ~= false)
		if not job.success then
			publish_decision_state("job_returned_false")
			action:warn(string.format("fsm job '%s' finished with false", name))
			return
		end

		publish_decision_state("job_succeeded")
	end)
end

local function take_request(name)
	local value = requests[name]
	requests[name] = false
	return value
end

local function set_state(name)
	runtime.current_state = name
	publish_decision_state("state_enter")
	action:info("fsm state -> " .. name)
end

local function start_runtime()
	runtime.navigation_ready = true
	set_reason("sim_start")
	return true, "ok"
end

local function clear_navigate_history()
	local queue = blackboard.meta.navigate_point_queue
	if type(queue) ~= "table" then
		blackboard.meta.navigate_point_queue = {}
		return
	end

	for i = #queue, 1, -1 do
		queue[i] = nil
	end
end

local function create_intent_fsm()
	local State = {
		idle = "idle",
		start_cruise = "start_cruise",
		keep_cruise = "keep_cruise",
		escape = "escape",
		recover = "recover",
	}

	local condition = blackboard.condition
	local intent_fsm = fsm:new(State.idle)
	local function restart_start_cruise_job()
		run_job("start_cruise", function()
			return start_cruise(runtime.ours_zone)
		end)
	end
	local function restart_keep_cruise_job()
		run_job("keep_cruise", function()
			return keep_cruise(runtime.ours_zone, runtime.switch_interval)
		end)
	end
	local function restart_escape_job()
		run_job("escape_to_home", function()
			return escape_to_home(runtime.ours_zone)
		end)
	end

	intent_fsm:use({
		state = State.idle,
		enter = function()
			cancel_job()
			set_state(State.idle)
			runtime.navigation_ready = false
		end,
		event = function(handle)
			if take_request("start") then
				local ok = start_runtime()
				runtime.navigation_ready = ok
			end

			if runtime.navigation_ready and blackboard.game.stage == "STARTED" then
				clear_navigate_history()
				set_reason("idle_to_start_cruise")
				handle:set_next(State.start_cruise)
			end
		end,
	})

	intent_fsm:use({
		state = State.start_cruise,
		enter = function()
			set_state(State.start_cruise)
			restart_start_cruise_job()
		end,
		event = function(handle)
			if condition.low_health() or condition.low_bullet() then
				cancel_job()
				set_reason("start_cruise_low_resource")
				handle:set_next(State.escape)
				return
			end

			if not job.done then
				return
			end

			if job.success then
				set_reason("start_cruise_done")
				handle:set_next(State.keep_cruise)
				return
			end

			action:warn("fsm(start_cruise): 导航失败，重试当前状态")
			set_reason("start_cruise_retry")
			restart_start_cruise_job()
		end,
	})

	intent_fsm:use({
		state = State.keep_cruise,
		enter = function()
			set_state(State.keep_cruise)
			restart_keep_cruise_job()
		end,
		event = function(handle)
			if condition.low_health() or condition.low_bullet() then
				cancel_job()
				set_reason("keep_cruise_low_resource")
				handle:set_next(State.escape)
				return
			end

			if not job.done then
				return
			end

			if job.success then
				return
			end

			action:warn("fsm(keep_cruise): 导航失败，重试当前状态")
			set_reason("keep_cruise_retry")
			restart_keep_cruise_job()
		end,
	})

	intent_fsm:use({
		state = State.escape,
		enter = function()
			set_state(State.escape)
			restart_escape_job()
		end,
		event = function(handle)
			if not job.done then
				return
			end

			if job.success then
				set_reason("escape_done")
				handle:set_next(State.recover)
				return
			end

			action:warn("fsm(escape): 导航失败，重试当前状态")
			set_reason("escape_retry")
			restart_escape_job()
		end,
	})

	intent_fsm:use({
		state = State.recover,
		enter = function()
			cancel_job()
			set_state(State.recover)
		end,
		event = function(handle)
			if condition.low_health() or condition.low_bullet() then
				return
			end

			if condition.health_ready() and condition.bullet_ready() then
				set_reason("recover_to_start_cruise")
				handle:set_next(State.start_cruise)
			end
		end,
	})

	assert(intent_fsm:init_ready(State), "intent fsm init_ready failed")
	return intent_fsm
end

on_init = function()
	ensure_schema()
	clock:reset(blackboard.meta.timestamp)

	option:set_handler(function(error)
		action:warn("while fetch option: " .. error)
	end)

	runtime.ours_zone = read_option("fsm_ours_zone", true)
	runtime.switch_interval = read_option("fsm_switch_interval", 2.0)

	configure_test_rule()
	publish_decision_state("initialized")

	if read_option("enable_goal_topic_forward", false) then
		action:switch_topic_forward(true)
	end
	action:bind(scheduler)

	local intent_fsm = create_intent_fsm()
	scheduler:append_task(function()
		while true do
			intent_fsm:spin_once()
			request:yield()
		end
	end)

	scheduler:append_task(function()
		while true do
			request:sleep(1.0)
			publish_decision_state("heartbeat")
			action:info(string.format(
				"fsm=%s stage=%s hp=%s bullet=%s",
				runtime.current_state,
				blackboard.game.stage,
				tostring(blackboard.user.health),
				tostring(blackboard.user.bullet)
			))
		end
	end)

	action:info(ascii.banner)
	action:warn("FSM test endpoint loaded (sim mode)")
end

on_tick = function()
	clock:update(blackboard.meta.timestamp)
	scheduler:spin_once()
end

on_exit = function()
	cancel_job()
end

--- Callback for simulated control feedback.
on_control = function(vx, vy, _)
	action:update_chassis_vel(vx, vy)
end

function on_sim_start(_, _)
	requests.start = true
	blackboard.game.stage = "STARTED"
	set_reason("sim_start_command")
end

function on_sim_set_target(_, _)
	-- train-decision currently uses rule points; dynamic target injection is ignored.
end
