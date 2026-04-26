local info = debug.getinfo(1, "S")
local script_path = info.source:sub(2)
local script_dir = script_path:match("(.*/)") or "./"
local test_util = dofile(script_dir .. "util.lua")
test_util.setup_package_path()

local assert_eq = test_util.assert_eq

package.loaded["blackboard"] = nil
package.loaded["blackboard_sync"] = nil

local Blackboard = require("blackboard")
local sync = require("blackboard_sync")
local bb = Blackboard.singleton()

bb.user.x = 1.5
bb.user.y = -0.5
bb.rule.decision = "forward"
bb.result.status = "idle"
bb.result.flags = { "a", "b" }

local snapshot = sync.snapshot()
assert_eq(snapshot.user.x, 1.5, "snapshot should include user.x")
assert_eq(snapshot.rule.decision, "forward", "snapshot should include rule")
assert_eq(snapshot.result.flags[2], "b", "snapshot should include nested arrays")
assert_eq(snapshot.condition, nil, "snapshot should skip function tables")

bb.user.x = 9.0
bb.result.status = "stale"
bb.result.extra = "keep"
bb.rule.decision = "back"

sync.apply({
	user = {
		x = 2.0,
		y = 3.0,
	},
	rule = {
		decision = "hold",
	},
	result = {
		status = "fresh",
	},
})

assert_eq(bb.user.x, 2.0, "apply should overwrite user.x")
assert_eq(bb.user.y, 3.0, "apply should overwrite user.y")
assert_eq(bb.rule.decision, "hold", "apply should overwrite rule fields")
assert_eq(bb.result.status, "fresh", "apply should overwrite result fields")
assert_eq(bb.result.extra, nil, "apply should remove missing result fields")

print("blackboard_sync.lua: ok")
