local info = debug.getinfo(1, "S")
local script_path = info.source:sub(2)
local script_dir = script_path:match("(.*/)") or "./"
local test_util = dofile(script_dir .. "util.lua")
test_util.setup_package_path()

local assert_eq = test_util.assert_eq
local assert_true = test_util.assert_true

local api = require("api")

local tmux_session = "navigation"

local function session_exists()
	local ok, _, code = os.execute("tmux has-session -t " .. tmux_session .. " 2>/dev/null")
	return ok == true or ok == 0 or code == 0
end

local function sleep_for(seconds)
	os.execute(string.format("sleep %.1f", seconds))
end

local function read_tmux_output()
	for _ = 1, 20 do
		local handle = io.popen("tmux capture-pane -t " .. tmux_session .. " -p -S -120 2>/dev/null")
		if handle then
			local content = handle:read("*a")
			handle:close()
			if content ~= nil and content ~= "" then
				return content
			end
		end
		sleep_for(0.1)
	end
	assert_true(false, "restart_navigation should produce tmux output")
end

local function print_tmux_output()
	local content = read_tmux_output()
	print("restart_navigation.lua: tmux output begin")
	print(content)
	print("restart_navigation.lua: tmux output end")
end

local function kill_session()
	os.execute("tmux kill-session -t " .. tmux_session .. " 2>/dev/null || true")
end

local function cleanup()
	kill_session()
end

test_util.with_cleanup(cleanup, function()
	cleanup()

	local ok, message = api.restart_navigation({
		launch_livox = false,
		launch_odin1 = false,
		global_map = "rmul",
		use_sim_time = false,
	})
	assert_true(ok, "restart_navigation should dispatch successfully")
	assert_eq(message, "ok", "restart_navigation dispatch result")

	local deadline = os.time() + 3
	while os.time() <= deadline do
		if session_exists() then
			sleep_for(1.0)
			print_tmux_output()
			kill_session()
			assert_true(not session_exists(), "restart_navigation should stop session after inspection")
			print("restart_navigation.lua: ok")
			return
		end
		sleep_for(0.1)
	end

	error("restart_navigation should create navigation tmux session")
end)
