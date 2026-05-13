local blackboard = require("blackboard").singleton()
local request = require("util.scheduler").request
local action = require("action")

--- 下坡任务。
---
--- 流程：
---  1. 正常导航到坡顶
---  2. 切换到 SlopeController（限制速度变化率，防前倾）
---  3. 导航到坡底
---  4. 恢复 normal 控制器
---
--- @param from {x: number, y: number}
--- @param to {x: number, y: number}
return function(from, to)
	local condition = blackboard.condition

	action:navigate(from)
	request:wait_until {
		monitor = function()
			return condition.near(from, 0.3)
		end,
		timeout = 10,
	}

	action:update_controller("slope")

	action:navigate(to)
	request:wait_until {
		monitor = function()
			return condition.near(to, 0.5)
		end,
		timeout = 15,
	}

	action:update_controller("normal")
	action:clear_target()
end
