---
--- Local Context
---

local api = require("api")
local ascii = require("util.ascii_art")
local clock = require("util.clock")
local edges = require("util.edge").new()

local Scheduler = require("util.scheduler")
local scheduler = Scheduler.new()
local request = Scheduler.request

---
--- Export Context
---

blackboard = require("blackboard").singleton()

on_init = function()
	api.info(ascii.banner)
	api.warn("⚠️ MOCK 模式，别上场哦")

	clock:reset(blackboard.meta.timestamp)
	api.switch_topic_forward(true)

	edges:on(blackboard.getter.rswitch, "UP", function()
		api.warn("导航即将重启")
		api.restart_navigation {
			launch_livox = true,
			launch_odin1 = false,
			global_map = "empty",
			use_sim_time = true,
		}
	end)

	scheduler:append_task(function()
		while true do
			request:sleep(1)
		end
	end)
end

on_tick = function()
	clock:update(blackboard.meta.timestamp)

	edges:spin()
	scheduler:spin_once()
end

on_exit = function()
	api.stop_navigation()
end

--- 由 NAV2 发布的目标速度值，在此处理回调
on_control = function(x, y, _)
	api.update_chassis_vel(x, y)
end
