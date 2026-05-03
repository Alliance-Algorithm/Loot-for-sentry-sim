local action = require("action")
local cross_road_zone = require("task.cross-road.cross-road-zone")

--- 训练专用旧入口兼容：
--- 保持 train-decision.lua 旧的函数式调用契约，
--- 内部桥接到当前 train 路线的公路区通过任务。
--- @param ours_zone boolean
--- @return boolean is_success
return function(ours_zone)
	assert(type(ours_zone) == "boolean", "ours_zone should be a boolean")
	action:info("开始start-cruise-train")

	local ok = cross_road_zone(ours_zone, true)
	if not ok then
		action:warn("start-cruise-train: 通过公路区训练路线失败")
		return false
	end

	action:info("start-cruise-train: 已完成公路区训练路线")
	return true
end
