---
--- Local Context
---

local action = require("action")
local ascii = require("util.ascii_art")
local clock = require("util.clock")
local fsm = require("util.fsm")
local option = require("option")

local Scheduler = require("util.scheduler")
local scheduler = Scheduler.new()
local request = Scheduler.request

local edges = require("util.edge").new()

---
--- Export Context
---

blackboard = require("blackboard").singleton()

on_init = function()
	clock:reset(blackboard.meta.timestamp)

	action:bind(scheduler)
	action:info("use decision: '" .. option.decision .. "'")

	option:set_handler(function(error)
		action:fuck("while fetch option: " .. error)
	end)

	if option.enable_goal_topic_forward then
		action:switch_topic_forward(true)
	end

	scheduler:append_task(function()
		local Intent = {
			nothing = "nothing",
		}
		local intent_fsm = fsm:new(Intent.nothing)

		intent_fsm:use {
			state = Intent.nothing,
			enter = function()
				action:warn("⚠️你来到了没有意图的荒原")
			end,
			event = function(handle)
				handle:set_next(Intent.nothing)
			end,
		}
		if not intent_fsm:init_ready(Intent) then
			error("意图状态机没有初始化完全，有未使用的意图")
		end

		while true do
			intent_fsm:spin_once()
			request:yield()
		end
	end)

	edges:on(blackboard.getter.rswitch, "UP", function()
		action:restart_navigation({
			launch_livox = false,
			launch_odin1 = false,
			global_map = "rmul",
			use_sim_time = false,
		})
	end)

	action:info(ascii.banner)
end

on_tick = function()
	clock:update(blackboard.meta.timestamp)

	edges:spin()
	scheduler:spin_once()
end

on_exit = function()
	action:stop_navigation()
end

--- 由 NAV2 发布的目标速度值，在此处理回调
on_control = function(vx, vy, qx)
	local _ = qx
	action:update_chassis_vel(vx, vy)
end
