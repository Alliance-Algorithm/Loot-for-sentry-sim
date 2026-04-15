---
--- Local Context
---

local api = require("api")
local ascii = require("util.ascii_art")
local clock = require("util.clock")

local Scheduler = require("util.scheduler")
local scheduler = Scheduler.new()
local request = Scheduler.request

---
--- Export Context
---

blackboard = require("blackboard").singleton()

on_init = function()
	api.info(ascii.banner)

	clock:reset(blackboard.meta.timestamp)
	api.switch_topic_forward(true)

	scheduler:append_task(function()
		request:sleep(0.5)
	end)

	api.restart_navigation {
		launch_livox = false,
		launch_odin1 = false,
		global_map = "rmul",
		use_sim_time = true,
	}
end

on_tick = function()
	clock:update(blackboard.meta.timestamp)

	scheduler:spin_once()
end

on_exit = function()
	api.stop_navigation()
end

--- 由 NAV2 发布的目标速度值，在此处理回调
on_control = function(_, _, _) end
