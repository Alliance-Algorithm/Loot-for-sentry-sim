local action = require("action")
local ascii = require("util.ascii_art")
local clock = require("util.clock")

local Scheduler = require("util.scheduler")
local scheduler = Scheduler.new()
local request = Scheduler.request

blackboard = require("blackboard").singleton()

local sim = {
	started = false,
	target = { x = 3.0, y = 0.0 },
}

on_init = function()
	action:info(ascii.banner)
	action:warn("SIM TEST MODE")

	clock:reset(0)
	blackboard.game.stage = "NOT_START"
	action:bind(scheduler)
end

function on_sim_set_target(x, y)
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
	blackboard.game.stage = "STARTED"

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
		blackboard.game.stage = "NOT_START"
	end)
end

on_tick = function()
	clock:update(blackboard.meta.timestamp)
	scheduler:spin_once()
end

on_exit = function()
	sim.started = false
	blackboard.game.stage = "NOT_START"
end

