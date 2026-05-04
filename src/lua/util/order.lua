local clock = require("util.clock")

---@class OrderEntry
---@field sequence any[]
---@field callback fun()
---@field step integer
---@field last_time number|nil

---@class Order
---@field private _getter fun(): any
---@field private _interval number
---@field private _entries OrderEntry[]
---@field private _last_value any
local Order = {}
Order.__index = Order

local function reset_entry(entry)
	entry.step = 0
	entry.last_time = nil
end

local function prime_entry(entry, value)
	reset_entry(entry)
	if value == entry.sequence[1] then
		entry.step = 1
	end
end

local function spin_entry(entry, value, interval, now)
	if entry.step > 1 and entry.last_time ~= nil and now - entry.last_time > interval then
		reset_entry(entry)
	end

	local first = entry.sequence[1]
	if entry.step == 0 then
		prime_entry(entry, value)
		if #entry.sequence == 1 and value == first then
			entry.callback()
		end
		return
	end

	local expected = entry.sequence[entry.step + 1]
	if value == expected then
		if entry.step + 1 == #entry.sequence then
			entry.callback()
			prime_entry(entry, value)
			return
		end

		entry.step = entry.step + 1
		if entry.step == 2 or entry.step > 2 then
			entry.last_time = now
		end
		return
	end

	prime_entry(entry, value)
	if #entry.sequence == 1 and value == first then
		entry.callback()
	end
end

---@param sequence any[]
---@param callback fun()
---@return Order
function Order:on(sequence, callback)
	local entry = {
		sequence = sequence,
		callback = callback,
		step = 0,
		last_time = nil,
	}
	prime_entry(entry, self._last_value)
	self._entries[#self._entries + 1] = entry
	return self
end

function Order:spin()
	local value = self._getter()
	if value == self._last_value then
		return
	end

	self._last_value = value
	local now = clock:now()
	for _, entry in ipairs(self._entries) do
		spin_entry(entry, value, self._interval, now)
	end
end

function Order:reset()
	self._last_value = self._getter()
	for _, entry in ipairs(self._entries) do
		prime_entry(entry, self._last_value)
	end
end

return {
	---@param getter fun(): any
	---@param interval number
	---@return Order
	new = function(getter, interval)
		return setmetatable({
			_getter = getter,
			_interval = interval,
			_entries = {},
			_last_value = getter(),
		}, Order)
	end,
}
