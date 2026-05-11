local blackboard = require("blackboard").singleton()

local sections = {
	"user",
	"game",
	"play",
	"meta",
	"rule",
	"result",
}

local function is_serializable(value)
	local value_type = type(value)
	return value_type == "nil"
		or value_type == "boolean"
		or value_type == "number"
		or value_type == "string"
		or value_type == "table"
end

local function deep_copy(value)
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, entry in pairs(value) do
		local key_type = type(key)
		if (key_type == "string" or key_type == "number") and is_serializable(entry) then
			copy[key] = deep_copy(entry)
		end
	end

	return copy
end

local function replace_table(target, source)
	for key in pairs(target) do
		if source[key] == nil then
			target[key] = nil
		end
	end

	for key, value in pairs(source) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {}
			end
			replace_table(target[key], value)
		else
			target[key] = value
		end
	end
end

local M = {}

function M.snapshot()
	local snapshot = {}
	for _, section in ipairs(sections) do
		snapshot[section] = deep_copy(blackboard[section])
	end
	return snapshot
end

function M.apply(snapshot)
	if type(snapshot) ~= "table" then
		return
	end

	for _, section in ipairs(sections) do
		local source = snapshot[section]
		if source ~= nil then
			if type(source) == "table" then
				if type(blackboard[section]) ~= "table" then
					blackboard[section] = {}
				end
				replace_table(blackboard[section], source)
			else
				blackboard[section] = source
			end
		end
	end
end

return M
