-------------------------------
-------------------------------
-- @brief 旧版仿真入口，已弃用！！！
-------------------------------
-------------------------------
local action = require("action")
local ascii = require("util.ascii_art")
local clock = require("util.clock")

local Scheduler = require("util.scheduler")
local scheduler = Scheduler.new()
local request = Scheduler.request

local blackboard = require("blackboard").singleton()

local sim = {
	started = false,
	target = { x = 3.0, y = 0.0 },
}

on_init = function()
	action:info(ascii.banner)
	action:warn("SIM SIDECAR MODE")
	clock:reset(blackboard.meta.timestamp)
	action:bind(scheduler)
end

function on_sim_set_target(x, y)
	if x == nil or y == nil then
		return
	end
	sim.target = { x = x, y = y }
end

function on_sim_start(x, y)
	if sim.started then
		return
	end

	if x ~= nil and y ~= nil then
		sim.target = { x = x, y = y }
	end

	sim.started = true

	scheduler:append_task(function()
		action:info(string.format("start -> target(%.2f, %.2f)", sim.target.x, sim.target.y))
		action:navigate(sim.target)

		local timeout = request:wait_until {
			monitor = function()
				return blackboard.condition.near(sim.target, 0.1)
			end,
			timeout = 30,
		}

		if timeout then
			action:warn("goal timeout")
		else
			action:info("goal reached")
		end

		sim.started = false
	end)
end

on_tick = function()
	clock:update(blackboard.meta.timestamp)
	scheduler:spin_once()
end

on_exit = function()
	sim.started = false
end

on_control = function(vx, vy, _)
	action:update_chassis_vel(vx, vy)
end
