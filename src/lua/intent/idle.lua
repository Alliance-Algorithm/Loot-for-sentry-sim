--- 意图：待命（比赛未开始）
---
--- 此状态只在比赛阶段非 STARTED 时存在。
--- 不执行任何导航操作，等待外部边缘触发切换到巡航。

local action = require("action")
local fsm = require("util.fsm")

local M = {}

local function new_phase_driver(phase)
	local driver = {
		phase_fsm = fsm:new(phase),
	}

	driver.phase_fsm:use {
		state = phase,
		event = function(handle)
			handle:set_next(phase)
		end,
	}

	function driver:enter()
		self.phase_fsm:start_on(phase)
		M.enter()
	end

	function driver:spin_once()
		self.phase_fsm:spin_once()
	end

	function driver:phase()
		return self.phase_fsm.details.current_state
	end

	return driver
end

function M.enter()
	action:info("[IDLE] 比赛尚未开始，待命中...")
end

function M.event(handle)
	handle:set_next("idle")
end

function M.new()
	return new_phase_driver("hold")
end

return M
