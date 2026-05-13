--- 意图：撤退回家（低血量 / 手动触发）
---
--- 导航至堡垒/基地补充血量和弹药。
--- 撤退期间不主动交战，优先安全回防。

local action = require("action")
local blackboard = require("blackboard").singleton()

local M = {}

function M.enter()
	action:warn("[ESCAPE] 撤退回家")
	local fortress = blackboard.rule.fortress.ours
	action:navigate(fortress)
end

function M.event(handle)
	-- 撤退中保持当前状态，由外部边缘（health_ready/bullet_ready）触发切换
	handle:set_next("escape_to_home")
end

return M
