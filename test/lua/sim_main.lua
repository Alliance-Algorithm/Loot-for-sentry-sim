local info = debug.getinfo(1, "S")
local script_path = info.source:sub(2)
local script_dir = script_path:match("(.*/)") or "./"
local test_util = dofile(script_dir .. "util.lua")
test_util.setup_package_path()

local assert_eq = test_util.assert_eq
local assert_table_eq = test_util.assert_table_eq

local calls = {
	send_target = {},
	update_chassis_vel = {},
	log = {},
}

package.loaded["api"] = {
	info = function(message)
		calls.log[#calls.log + 1] = { "info", message }
	end,
	warn = function(message)
		calls.log[#calls.log + 1] = { "warn", message }
	end,
	fuck = function(message)
		calls.log[#calls.log + 1] = { "error", message }
	end,
	send_target = function(x, y)
		calls.send_target[#calls.send_target + 1] = { x, y }
	end,
	update_gimbal_direction = function(_) end,
	update_gimbal_dominator = function(_) end,
	update_chassis_mode = function(_) end,
	update_chassis_vel = function(x, y)
		calls.update_chassis_vel[#calls.update_chassis_vel + 1] = { x, y }
	end,
	restart_navigation = function()
		return true, "ok"
	end,
	stop_navigation = function()
		return true, "ok"
	end,
	switch_topic_forward = function(_) end,
}

package.loaded["blackboard"] = nil
package.loaded["option"] = nil
package.loaded["main"] = nil
local Blackboard = require("blackboard")
local bb = Blackboard.singleton()

bb.meta.timestamp = 0
bb.user.x = 0
bb.user.y = 0

require("endpoint.sim_main")
on_init()

on_sim_set_target(2.0, -1.0)
on_sim_start()

local function tick(now, x, y)
	bb.meta.timestamp = now
	if x ~= nil then
		bb.user.x = x
	end
	if y ~= nil then
		bb.user.y = y
	end
	on_tick()
end

tick(0.1, 0.0, 0.0)
tick(0.2, 0.0, 0.0)
assert_eq(#calls.send_target, 1, "sim start should trigger navigate action")
assert_table_eq(calls.send_target[1], { 2.0, -1.0 }, "target payload")

on_control(0.2, -0.3, 1.0)
assert_eq(#calls.update_chassis_vel, 1, "on_control should forward chassis velocity")
assert_table_eq(calls.update_chassis_vel[1], { 0.2, -0.3 }, "control velocity payload")

tick(1.0, 2.0, -1.0)
tick(1.1, 2.0, -1.0)

print("sim_main.lua: ok")
