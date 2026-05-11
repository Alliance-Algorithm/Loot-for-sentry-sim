local M = {}

function M.install(endpoint_name)
	local loot_probe = require("Loot.loot_probe")
	loot_probe.install()

	local config_name = "Loot.config." .. tostring(endpoint_name)
	local ok, config = pcall(require, config_name)
	if not ok then
		return {
			snapshot = function()
				return loot_probe.snapshot()
			end,
		}
	end

	local probe = require("Loot.probe").new(config, loot_probe)
	return {
		snapshot = function()
			return probe:snapshot()
		end,
	}
end

return M
