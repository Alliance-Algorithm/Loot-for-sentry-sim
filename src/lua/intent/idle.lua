--- 意图：待命（比赛未开始）
---
--- 此状态只在比赛阶段非 STARTED 时存在。
--- 不执行任何导航操作，等待外部边缘触发切换到巡航。

local action = require("action")

local M = {}

function M.enter()
	action:info("[IDLE] 比赛尚未开始，待命中...")
end

function M.event(handle)
	handle:set_next("idle")
end

return M
