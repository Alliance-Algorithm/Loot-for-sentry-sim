local M = {}

local installed = false
local current_task_id = nil

local state = {
	serial = 0,
	fsm_next_id = 0,
	fsm_spin_serial = 0,
	task_next_id = 0,
	scheduler_next_id = 0,
	edge_next_id = 0,
	events = {},
	fsms = {},
	tasks = {},
	edges = {},
	decision_graph = {
		id = "decision",
		label = "Decision Graph",
		nodes = {},
		edges = {},
		active_nodes = {},
		active_edges = {},
		active_status = {},
		failures = {},
		current_state = nil,
		current_intent = nil,
		current_phase = nil,
		revision = 0,
		updated_at = 0,
	},
	actions = {
		last = nil,
		nav_target = nil,
		nav_history = {},
	},
}

local max_events = 80
local max_nav_history = 32
local max_failures = 8

local function now()
	local ok, blackboard = pcall(function()
		return require("blackboard").singleton()
	end)
	if ok and type(blackboard) == "table" and type(blackboard.meta) == "table" then
		return blackboard.meta.timestamp or 0
	end
	return 0
end

local function push_limited(array, value, limit)
	array[#array + 1] = value
	while #array > limit do
		table.remove(array, 1)
	end
end

local function emit(kind, payload)
	state.serial = state.serial + 1
	local event = {
		id = state.serial,
		time = now(),
		kind = kind,
	}
	if type(payload) == "table" then
		for key, value in pairs(payload) do
			event[key] = value
		end
	end
	push_limited(state.events, event, max_events)
	return event
end

local function next_id(name)
	state[name] = state[name] + 1
	return state[name]
end

local function function_source(fn)
	local info = debug.getinfo(fn, "Sl")
	if info == nil then
		return "unknown", 0
	end
	local source = info.source or info.short_src or "unknown"
	if string.sub(source, 1, 1) == "@" then
		source = string.sub(source, 2)
	end
	return source, info.linedefined or 0
end

local function sorted_values(map)
	local ids = {}
	for id in pairs(map) do
		ids[#ids + 1] = id
	end
	table.sort(ids)

	local result = {}
	for _, id in ipairs(ids) do
		result[#result + 1] = map[id]
	end
	return result
end

local function shallow_copy_array(values)
	local result = {}
	for index, value in ipairs(values or {}) do
		result[index] = value
	end
	return result
end

local function copy_plain_value(value, depth)
	if type(value) ~= "table" then
		return value
	end
	if depth >= 6 then
		return nil
	end

	local result = {}
	for key, nested in pairs(value) do
		result[key] = copy_plain_value(nested, depth + 1)
	end
	return result
end

local function copy_plain_table(value)
	if type(value) ~= "table" then
		return {}
	end
	return copy_plain_value(value, 0) or {}
end

local function sorted_observed_edges(map)
	local keys = {}
	for key in pairs(map or {}) do
		keys[#keys + 1] = key
	end
	table.sort(keys)

	local result = {}
	for _, key in ipairs(keys) do
		local edge = map[key]
		result[#result + 1] = {
			from = edge.from,
			to = edge.to,
			count = edge.count,
			last_time = edge.last_time,
			last_reason = edge.last_reason,
			source = edge.source,
			line = edge.line,
		}
	end
	return result
end

local function sorted_declared_edges(map)
	local keys = {}
	for key in pairs(map or {}) do
		keys[#keys + 1] = key
	end
	table.sort(keys)

	local result = {}
	for _, key in ipairs(keys) do
		local edge = map[key]
		result[#result + 1] = {
			from = edge.from,
			to = edge.to,
			label = edge.label,
			source = edge.source,
			line = edge.line,
		}
	end
	return result
end

local function sorted_fsm_values(map)
	local ids = {}
	for id in pairs(map) do
		ids[#ids + 1] = id
	end
	table.sort(ids)

	local result = {}
	for _, id in ipairs(ids) do
		local entry = map[id]
		result[#result + 1] = {
			id = entry.id,
			label = entry.label,
			current_state = entry.current_state,
			last_state = entry.last_state,
			source = entry.source,
			line = entry.line,
			states = shallow_copy_array(entry.states),
			state_sources = copy_plain_table(entry.state_sources),
			spin_count = entry.spin_count,
			last_spin_serial = entry.last_spin_serial,
			last_spin_time = entry.last_spin_time,
			transition_count = entry.transition_count,
			last_transition = entry.last_transition,
			observed_edges = sorted_observed_edges(entry.observed_edges),
			declared_edges = sorted_declared_edges(entry.declared_edges),
		}
	end
	return result
end

local function call_source(level)
	local info = debug.getinfo(level or 3, "Sl")
	if info == nil then
		return "unknown", 0
	end
	local source = info.source or info.short_src or "unknown"
	if string.sub(source, 1, 1) == "@" then
		source = string.sub(source, 2)
	end
	return source, info.currentline or info.linedefined or 0
end

local function ensure_fsm_entry(fsm, source, line)
	if type(fsm) ~= "table" then
		return nil
	end
	local details = fsm.details
	if type(details) ~= "table" then
		return nil
	end

	local id = rawget(fsm, "__loot_id")
	if id == nil then
		id = next_id("fsm_next_id")
		rawset(fsm, "__loot_id", id)
		state.fsms[id] = {
			id = id,
			label = "fsm#" .. tostring(id),
			source = source or "unknown",
			line = line or 0,
			current_state = tostring(details.current_state),
			last_state = details.last_state,
			states = {},
			state_sources = {},
			spin_count = 0,
			last_spin_serial = 0,
			last_spin_time = 0,
			transition_count = 0,
			last_transition = nil,
			observed_edges = {},
			declared_edges = {},
		}
	elseif source ~= nil and source ~= "unknown" then
		local entry = state.fsms[id]
		if entry.source == nil or entry.source == "unknown" then
			entry.source = source
			entry.line = line or 0
		end
	end
	return state.fsms[id]
end

local function edge_key(from, to)
	return tostring(from) .. "\n" .. tostring(to)
end

local function record_declared_edges(entry, state_name, config)
	if type(entry) ~= "table" or type(config) ~= "table" or type(config.transitions) ~= "table" then
		return
	end

	local source, line = "unknown", 0
	if type(config.event) == "function" then
		source, line = function_source(config.event)
	end

	for _, transition in ipairs(config.transitions) do
		if type(transition) == "table" and transition.to ~= nil then
			local from_state = tostring(transition.from or state_name)
			local to_state = tostring(transition.to)
			local key = edge_key(from_state, to_state)
			entry.declared_edges[key] = {
				from = from_state,
				to = to_state,
				label = transition.label,
				source = transition.source or source,
				line = transition.line or line,
			}
		elseif transition ~= nil then
			local from_state = tostring(state_name)
			local to_state = tostring(transition)
			local key = edge_key(from_state, to_state)
			entry.declared_edges[key] = {
				from = from_state,
				to = to_state,
				label = nil,
				source = source,
				line = line,
			}
		end
	end
end

local function record_fsm_transition(entry, from, to, detail)
	if entry == nil or from == nil or to == nil then
		return nil
	end

	local from_state = tostring(from)
	local to_state = tostring(to)
	if from_state == "" or to_state == "" then
		return nil
	end

	local time = detail and detail.time or now()
	local transition = {
		from = from_state,
		to = to_state,
		time = time,
	}

	if type(detail) == "table" then
		if detail.reason ~= nil then
			transition.reason = detail.reason
		end
		if detail.source ~= nil then
			transition.source = detail.source
		end
		if detail.line ~= nil then
			transition.line = detail.line
		end
	end

	entry.transition_count = entry.transition_count + 1
	entry.last_transition = transition

	local key = edge_key(from_state, to_state)
	local edge = entry.observed_edges[key]
	if edge == nil then
		edge = {
			from = from_state,
			to = to_state,
			count = 0,
			last_time = 0,
			last_reason = nil,
			source = nil,
			line = nil,
		}
		entry.observed_edges[key] = edge
	end

	edge.count = edge.count + 1
	edge.last_time = time
	if transition.reason ~= nil then
		edge.last_reason = transition.reason
	end
	if transition.source ~= nil then
		edge.source = transition.source
	end
	if transition.line ~= nil then
		edge.line = transition.line
	end

	return transition
end

local function patch_fsm_handle(fsm, entry)
	if type(fsm) ~= "table" or type(entry) ~= "table" then
		return
	end
	local details = fsm.details
	if type(details) ~= "table" or type(details.handle) ~= "table" then
		return
	end
	local handle = details.handle
	if rawget(handle, "__loot_patched") then
		return
	end
	local original_set_next = handle.set_next
	if type(original_set_next) ~= "function" then
		return
	end
	rawset(handle, "__loot_patched", true)
	handle.set_next = function(self, status, reason)
		local current = details.current_state
		local source, line = call_source(3)
		local result = original_set_next(self, status)
		if status ~= nil and current ~= status then
			entry.pending_transition_detail = {
				from = tostring(current),
				to = tostring(status),
				reason = reason,
				source = source,
				line = line,
				time = now(),
			}
		end
		return result
	end
end

local function install_fsm_probe()
	local ok, Fsm = pcall(require, "util.fsm")
	if not ok or type(Fsm) ~= "table" or rawget(Fsm, "__loot_patched") then
		return
	end
	rawset(Fsm, "__loot_patched", true)

	local original_new = Fsm.new
	local original_use = Fsm.use
	local original_spin_once = Fsm.spin_once
	local original_start_on = Fsm.start_on

	function Fsm:new(start_state)
		local source, line = call_source(3)
		local fsm = original_new(self, start_state)
		local entry = ensure_fsm_entry(fsm, source, line)
		if entry ~= nil then
			patch_fsm_handle(fsm, entry)
			entry.source = source
			entry.line = line
			entry.current_state = tostring(start_state)
			emit("fsm.new", {
				fsm_id = entry.id,
				state = tostring(start_state),
				source = source,
				line = line,
			})
		end
		return fsm
	end

	function Fsm:use(config)
		local entry = ensure_fsm_entry(self)
		if entry ~= nil and type(config) == "table" and config.state ~= nil then
			patch_fsm_handle(self, entry)
			local state_name = tostring(config.state)
			local source, line = call_source(3)
			if type(config.event) == "function" then
				source, line = function_source(config.event)
			end
			local found = false
			for _, existing in ipairs(entry.states) do
				if existing == state_name then
					found = true
					break
				end
			end
			if not found then
				entry.states[#entry.states + 1] = state_name
				table.sort(entry.states)
			end
			entry.state_sources[state_name] = {
				source = source,
				line = line,
			}
			record_declared_edges(entry, state_name, config)
			emit("fsm.use", {
				fsm_id = entry.id,
				state = state_name,
				source = source,
				line = line,
			})
		end
		return original_use(self, config)
	end

	function Fsm:spin_once()
		local entry = ensure_fsm_entry(self)
		local details = self.details
		local before = details and details.current_state
		if entry ~= nil then
			patch_fsm_handle(self, entry)
			entry.spin_count = entry.spin_count + 1
			state.fsm_spin_serial = state.fsm_spin_serial + 1
			entry.last_spin_serial = state.fsm_spin_serial
			entry.last_spin_time = now()
		end

		local result = original_spin_once(self)

		if entry ~= nil and type(details) == "table" then
			local after = details.current_state
			entry.current_state = tostring(after)
			entry.last_state = details.last_state
			if before ~= after then
				record_fsm_transition(entry, before, after, entry.pending_transition_detail)
			end
			entry.pending_transition_detail = nil
			if before ~= after then
				emit("fsm.transition", {
					fsm_id = entry.id,
					from = tostring(before),
					to = tostring(after),
				})
			end
		end

		return result
	end

	function Fsm:start_on(target_state)
		local entry = ensure_fsm_entry(self)
		local before = self.details and self.details.current_state
		local result = original_start_on(self, target_state)
		if entry ~= nil then
			patch_fsm_handle(self, entry)
			entry.current_state = tostring(target_state)
			entry.last_state = nil
			record_fsm_transition(entry, before, target_state, {
				reason = "start_on",
			})
			emit("fsm.start_on", {
				fsm_id = entry.id,
				from = tostring(before),
				to = tostring(target_state),
			})
		end
		return result
	end
end

local function install_scheduler_probe()
	local ok, Scheduler = pcall(require, "util.scheduler")
	if not ok or type(Scheduler) ~= "table" or rawget(Scheduler, "__loot_patched") then
		return
	end
	rawset(Scheduler, "__loot_patched", true)

	local original_new = Scheduler.new
	local original_request_yield = Scheduler.request.yield
	local original_request_sleep = Scheduler.request.sleep
	local original_request_wait_until = Scheduler.request.wait_until

	local function task_entry(id)
		if id == nil then
			return nil
		end
		return state.tasks[id]
	end

	local function mark_wait(kind, extra)
		local task = task_entry(current_task_id)
		if task == nil then
			return
		end
		task.wait_kind = kind
		task.wait_since = now()
		task.wait_until = nil
		if type(extra) == "table" then
			for key, value in pairs(extra) do
				task[key] = value
			end
		end
		emit("task.wait", {
			task_id = task.id,
			kind = kind,
		})
	end

	function Scheduler.request:yield()
		mark_wait("yield")
		local result = original_request_yield(self)
		local task = task_entry(current_task_id)
		if task ~= nil then
			task.wait_kind = "running"
			task.wait_until = nil
		end
		return result
	end

	function Scheduler.request:sleep(seconds)
		mark_wait("sleep", {
			wait_until = now() + seconds,
		})
		local result = original_request_sleep(self, seconds)
		local task = task_entry(current_task_id)
		if task ~= nil then
			task.wait_kind = "running"
			task.wait_until = nil
		end
		return result
	end

	function Scheduler.request:wait_until(args)
		local timeout = nil
		if type(args) == "table" and type(args.timeout) == "number" then
			timeout = now() + args.timeout
		end
		mark_wait("wait_until", {
			wait_until = timeout,
		})
		local result = original_request_wait_until(self, args)
		local task = task_entry(current_task_id)
		if task ~= nil then
			task.wait_kind = "running"
			task.wait_until = nil
			task.last_wait_timeout = result
		end
		return result
	end

	local function patch_instance(instance)
		if rawget(instance, "__loot_patched") then
			return instance
		end
		rawset(instance, "__loot_patched", true)

		local scheduler_id = next_id("scheduler_next_id")
		rawset(instance, "__loot_id", scheduler_id)

		local metatable = getmetatable(instance)
		local prototype = metatable and metatable.__index
		local original_append_task = prototype and prototype.append_task
		if type(original_append_task) ~= "function" then
			return instance
		end

		function instance:append_task(fn)
			local task_id = next_id("task_next_id")
			local source, line = function_source(fn)
			local handle = original_append_task(self, fn)
			local task = self.details.tasks[#self.details.tasks]
			rawset(task, "__loot_id", task_id)
			rawset(task, "__loot_scheduler_id", scheduler_id)

			state.tasks[task_id] = {
				id = task_id,
				scheduler_id = scheduler_id,
				label = "task#" .. tostring(task_id),
				source = source,
				line = line,
				status = "ready",
				wait_kind = "ready",
				wait_since = now(),
				wait_until = nil,
				resume_count = 0,
				last_error = nil,
			}
			emit("task.append", {
				task_id = task_id,
				scheduler_id = scheduler_id,
				source = source,
				line = line,
			})

			if type(handle) == "table" and type(handle.cancel) == "function" then
				local original_cancel = handle.cancel
				function handle.cancel()
					local entry = state.tasks[task_id]
					if entry ~= nil then
						entry.status = "cancelled"
						entry.wait_kind = "cancelled"
					end
					emit("task.cancel", {
						task_id = task_id,
					})
					return original_cancel()
				end
			end

			return handle
		end

		function instance:spin_once()
			local details = self.details
			local saved_tasks = {}

			for _, task in ipairs(details.tasks) do
				local task_id = rawget(task, "__loot_id")
				local entry = state.tasks[task_id]
				local status = coroutine.status(task.thread)
				local cancel = task.cancel_request()

				if entry ~= nil then
					entry.status = status
					if status == "dead" then
						entry.wait_kind = "dead"
					end
					if cancel then
						entry.status = "cancelled"
						entry.wait_kind = "cancelled"
					end
				end

				if status == "dead" or cancel then
					goto continue
				end

				if task.resume_request() then
					if entry ~= nil then
						entry.status = "running"
						entry.wait_kind = "running"
						entry.resume_count = entry.resume_count + 1
					end
					current_task_id = task_id
					local result, request = coroutine.resume(task.thread)
					current_task_id = nil
					if result ~= true then
						if entry ~= nil then
							entry.status = "error"
							entry.wait_kind = "error"
							entry.last_error = tostring(request)
						end
						emit("task.error", {
							task_id = task_id,
							message = tostring(request),
						})
						error(debug.traceback(task.thread, tostring(request)), 0)
					end

					if request ~= nil then
						task.resume_request = request.resume_request
					end

					if entry ~= nil then
						entry.status = coroutine.status(task.thread)
						if entry.status == "dead" then
							entry.wait_kind = "dead"
						end
					end
				end
				table.insert(saved_tasks, task)

				::continue::
			end
			details.tasks = saved_tasks
		end

		emit("scheduler.new", {
			scheduler_id = scheduler_id,
		})
		return instance
	end

	function Scheduler.new()
		return patch_instance(original_new())
	end
end

local function install_edge_probe()
	local ok, edge_module = pcall(require, "util.edge")
	if not ok or type(edge_module) ~= "table" or rawget(edge_module, "__loot_patched") then
		return
	end
	rawset(edge_module, "__loot_patched", true)

	local original_new = edge_module.new

	local function patch_instance(instance)
		if rawget(instance, "__loot_patched") then
			return instance
		end
		rawset(instance, "__loot_patched", true)

		local metatable = getmetatable(instance)
		local prototype = metatable and metatable.__index
		local original_on = prototype and prototype.on
		if type(original_on) ~= "function" then
			return instance
		end

		function instance:on(getter, signal, callback)
			local edge_id = next_id("edge_next_id")
			state.edges[edge_id] = {
				id = edge_id,
				signal = tostring(signal),
				trigger_count = 0,
				last_trigger_time = nil,
			}
			emit("edge.on", {
				edge_id = edge_id,
				signal = tostring(signal),
			})

			local function wrapped_callback(...)
				local entry = state.edges[edge_id]
				if entry ~= nil then
					entry.trigger_count = entry.trigger_count + 1
					entry.last_trigger_time = now()
				end
				emit("edge.trigger", {
					edge_id = edge_id,
					signal = tostring(signal),
				})
				return callback(...)
			end

			return original_on(self, getter, signal, wrapped_callback)
		end

		return instance
	end

	function edge_module.new()
		return patch_instance(original_new())
	end
end

local function action_args(name, args)
	if name == "navigate" and type(args[1]) == "table" then
		return {
			x = args[1].x,
			y = args[1].y,
		}
	end
	if name == "update_chassis_vel" then
		return {
			x = args[1],
			y = args[2],
		}
	end
	if name == "update_chassis_mode" then
		return {
			mode = args[1],
		}
	end
	if name == "update_gimbal_direction" then
		return {
			angle = args[1],
		}
	end
	if name == "update_gimbal_dominator" then
		return {
			name = args[1],
		}
	end
	if name == "switch_topic_forward" then
		return {
			enable = args[1],
		}
	end
	return {}
end

local function install_action_probe()
	local ok, action = pcall(require, "action")
	if not ok or type(action) ~= "table" or rawget(action, "__loot_patched") then
		return
	end
	rawset(action, "__loot_patched", true)

	local names = {
		"navigate",
		"restart_navigation",
		"stop_navigation",
		"update_chassis_vel",
		"update_chassis_mode",
		"update_gimbal_direction",
		"update_gimbal_dominator",
		"switch_topic_forward",
	}

	for _, name in ipairs(names) do
		local original = action[name]
		if type(original) == "function" then
			action[name] = function(self, ...)
				local args = { ... }
				local summary = action_args(name, args)
				local event = {
					name = name,
					time = now(),
					task_id = current_task_id,
					args = summary,
				}
				state.actions.last = event

				if name == "navigate" and summary.x ~= nil and summary.y ~= nil then
					state.actions.nav_target = {
						x = summary.x,
						y = summary.y,
					}
					push_limited(state.actions.nav_history, {
						x = summary.x,
						y = summary.y,
						time = event.time,
					}, max_nav_history)
				end

				emit("action." .. name, {
					task_id = current_task_id,
					x = summary.x,
					y = summary.y,
					value = summary.mode or summary.name,
				})
				return original(self, ...)
			end
		end
	end
end

function M.install()
	if installed then
		return true
	end
	installed = true

	install_fsm_probe()
	install_scheduler_probe()
	install_edge_probe()
	install_action_probe()

	emit("loot.install", {})
	return true
end

function M.declare_decision_graph(graph)
	if type(graph) ~= "table" then
		return false
	end

	local current = state.decision_graph
	current.id = tostring(graph.id or current.id or "decision")
	current.label = tostring(graph.label or current.label or "Decision Graph")
	current.nodes = copy_plain_table(graph.nodes)
	current.edges = copy_plain_table(graph.edges)
	current.revision = current.revision + 1
	current.updated_at = now()

	if type(graph.active_nodes) == "table" then
		current.active_nodes = copy_plain_table(graph.active_nodes)
	end
	if type(graph.active_edges) == "table" then
		current.active_edges = copy_plain_table(graph.active_edges)
	end
	if type(graph.active_status) == "table" then
		current.active_status = copy_plain_table(graph.active_status)
	end

	emit("decision_graph.declare", {
		graph_id = current.id,
		node_count = #current.nodes,
		edge_count = #current.edges,
	})
	return true
end

function M.set_decision_path(path)
	if type(path) ~= "table" then
		path = {}
	end

	local current = state.decision_graph
	current.active_nodes = copy_plain_table(path.nodes)
	current.active_edges = copy_plain_table(path.edges)
	current.active_status = copy_plain_table(path.status)
	current.current_state = path.current_state
	current.current_intent = path.current_intent
	current.current_phase = path.current_phase
	current.updated_at = now()

	emit("decision_graph.active", {
		graph_id = current.id,
		current_state = current.current_state,
		current_intent = current.current_intent,
		current_phase = current.current_phase,
	})
	return true
end

function M.record_decision_failure(failure)
	if type(failure) ~= "table" then
		return false
	end

	local current = state.decision_graph
	push_limited(current.failures, {
		time = now(),
		intent = failure.intent,
		task = failure.task,
	}, max_failures)
	current.updated_at = now()

	emit("decision_graph.failure", {
		graph_id = current.id,
		intent = failure.intent,
		task = failure.task,
	})
	return true
end

function M.snapshot()
	return {
		serial = state.serial,
		decision_graph = copy_plain_table(state.decision_graph),
		fsm = {
			items = sorted_fsm_values(state.fsms),
		},
		tasks = {
			items = sorted_values(state.tasks),
		},
		edges = {
			items = sorted_values(state.edges),
		},
		actions = {
			last = state.actions.last,
			nav_target = state.actions.nav_target,
			nav_history = shallow_copy_array(state.actions.nav_history),
		},
		events = shallow_copy_array(state.events),
	}
end

return M
