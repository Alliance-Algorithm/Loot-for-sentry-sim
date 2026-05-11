local M = {}
M.__index = M

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

local function entry_id(entry)
	if type(entry) == "table" then
		return entry.id or entry[1]
	end
	return entry
end

local function entry_label(entry, fallback)
	if type(entry) == "table" then
		return entry.label or entry.name or fallback
	end
	return fallback
end

local function normalize_source(source)
	source = tostring(source or "")
	if string.sub(source, 1, 1) == "@" then
		source = string.sub(source, 2)
	end
	return string.gsub(source, "\\", "/")
end

local function source_matches(source, suffix)
	source = normalize_source(source)
	suffix = normalize_source(suffix)
	if source == suffix then
		return true
	end
	return string.sub(source, -#suffix) == suffix
end

local function graph_edge_id(from, to)
	return tostring(from) .. " -> " .. tostring(to)
end

local function graph_edge(from, to, label)
	return {
		id = graph_edge_id(from, to),
		from = from,
		to = to,
		label = label,
	}
end

local function endpoint_node_id(endpoint)
	return "endpoint:" .. tostring(endpoint)
end

local function intent_node_id(intent)
	return "intent:" .. tostring(intent)
end

local function phase_node_id(intent, phase)
	return "phase:" .. tostring(intent) .. ":" .. tostring(phase)
end

local function endpoint_node(endpoint, label)
	return {
		id = endpoint_node_id(endpoint),
		label = label or endpoint,
		kind = "endpoint",
		level = 1,
	}
end

local function intent_node(intent, label)
	return {
		id = intent_node_id(intent),
		label = label or intent,
		kind = "intent",
		level = 2,
	}
end

local function phase_node(intent, phase, label)
	return {
		id = phase_node_id(intent, phase),
		label = label or phase,
		kind = "phase",
		level = 3,
	}
end

local function root_node(config)
	local root = config.root or {}
	return {
		id = root.id or "root",
		label = root.label or config.root_label or "root",
		kind = "root",
		level = 0,
	}
end

local function is_result_phase(phase)
	return phase == "done" or phase == "failed" or phase == "hold" or phase == "none"
end

local function resolve_endpoint_ref(config, endpoint)
	local root_id = (config.root and config.root.id) or "root"
	if endpoint == root_id or endpoint == "root" then
		return root_id
	end
	return endpoint_node_id(endpoint)
end

local function push_limited(array, value, limit)
	array[#array + 1] = value
	while #array > limit do
		table.remove(array, 1)
	end
end

local function fsm_items(raw)
	if type(raw) ~= "table" or type(raw.fsm) ~= "table" or type(raw.fsm.items) ~= "table" then
		return {}
	end
	return raw.fsm.items
end

local function fsm_matches_source(fsm, source)
	if source_matches(fsm.source, source) then
		return true
	end
	if type(fsm.state_sources) == "table" then
		for _, state_source in pairs(fsm.state_sources) do
			if type(state_source) == "table" and source_matches(state_source.source, source) then
				return true
			end
		end
	end
	return false
end

local function latest_fsm_by_source(raw, source)
	local latest = nil
	for _, fsm in ipairs(fsm_items(raw)) do
		if type(fsm) == "table" and fsm_matches_source(fsm, source) then
			if
				latest == nil
				or (fsm.last_spin_serial or 0) > (latest.last_spin_serial or 0)
				or (
					(fsm.last_spin_serial or 0) == (latest.last_spin_serial or 0)
					and (fsm.id or 0) > (latest.id or 0)
				)
			then
				latest = fsm
			end
		end
	end
	return latest
end

local function edge_key(from, to)
	return tostring(from) .. "\n" .. tostring(to)
end

local function declared_edges_for_fsm(config, fsm)
	local result = {}
	if type(fsm) ~= "table" or type(config.fsm_declared_edges) ~= "table" then
		return result
	end

	for _, group in ipairs(config.fsm_declared_edges) do
		if type(group) == "table" and fsm_matches_source(fsm, group.source) then
			for _, edge in ipairs(group.edges or {}) do
				if type(edge) == "table" and edge.from ~= nil and edge.to ~= nil then
					result[edge_key(edge.from, edge.to)] = {
						from = tostring(edge.from),
						to = tostring(edge.to),
						label = edge.label,
						source = group.source,
						line = edge.line or 0,
					}
				end
			end
		end
	end

	return result
end

local function phase_status(failed_latched, phase)
	if failed_latched then
		return "failed"
	end
	if phase == "failed" then
		return "failed"
	end
	if phase == "hold" then
		return "hold"
	end
	if phase == "done" then
		return "done"
	end
	return "running"
end

local function build_static_graph(config)
	local root = root_node(config)
	local nodes = { root }
	local edges = {}

	for _, endpoint in ipairs(config.endpoints or {}) do
		local id = entry_id(endpoint)
		nodes[#nodes + 1] = endpoint_node(id, entry_label(endpoint, id))
	end

	for _, intent in ipairs(config.intents or {}) do
		local intent_id = entry_id(intent)
		nodes[#nodes + 1] = intent_node(intent_id, entry_label(intent, intent_id))

		for _, phase in ipairs(intent.phases or {}) do
			local phase_id = entry_id(phase)
			nodes[#nodes + 1] = phase_node(intent_id, phase_id, entry_label(phase, phase_id))
			edges[#edges + 1] = graph_edge(
				intent_node_id(intent_id),
				phase_node_id(intent_id, phase_id),
				phase.edge_label or "phase"
			)
		end
	end

	for _, edge in ipairs(config.endpoint_edges or {}) do
		edges[#edges + 1] = graph_edge(
			resolve_endpoint_ref(config, edge.from),
			resolve_endpoint_ref(config, edge.to),
			edge.label
		)
	end

	for _, intent in ipairs(config.intents or {}) do
		local intent_id = entry_id(intent)
		if intent.endpoint ~= nil then
			edges[#edges + 1] = graph_edge(
				resolve_endpoint_ref(config, intent.endpoint),
				intent_node_id(intent_id),
				intent.edge_label
			)
		end
	end

	return nodes, edges
end

function M.new(config, loot_probe)
	assert(type(config) == "table", "Loot.probe config should be a table")
	assert(type(loot_probe) == "table", "Loot.probe needs Loot.loot_probe")

	local nodes, edges = build_static_graph(config)
	return setmetatable({
		config = config,
		loot_probe = loot_probe,
		nodes = nodes,
		edges = edges,
		failures = {},
		failed_latch = {},
		last_non_result_phase = {},
		revision = 1,
	}, M)
end

function M:record_failure(intent_id, task)
	if self.failed_latch[intent_id] then
		return
	end
	self.failed_latch[intent_id] = true
	push_limited(self.failures, {
		time = now(),
		intent = intent_id,
		task = task,
	}, max_failures)
end

function M:observe_intent(intent_id, fsm)
	if type(fsm) ~= "table" then
		return
	end

	local phase = tostring(fsm.current_state or "none")
	if not is_result_phase(phase) then
		-- Entering a running phase means this intent has started a fresh attempt,
		-- so the previous failed latch must not keep the graph red.
		self.failed_latch[intent_id] = false
		self.last_non_result_phase[intent_id] = phase
		return
	end

	if phase == "failed" then
		local task = self.last_non_result_phase[intent_id]
		if task == nil and type(fsm.last_state) == "string" and not is_result_phase(fsm.last_state) then
			task = fsm.last_state
		end
		self:record_failure(intent_id, task or phase)
		return
	end

	if phase == "done" then
		self.failed_latch[intent_id] = false
	end
end

function M:intent_runtime(raw)
	local by_intent = {}
	local active = nil

	for _, intent in ipairs(self.config.intents or {}) do
		local intent_id = entry_id(intent)
		local fsm = latest_fsm_by_source(raw, intent.source)
		by_intent[intent_id] = fsm
		self:observe_intent(intent_id, fsm)
		if
			type(fsm) == "table"
			and (fsm.last_spin_serial or 0) > 0
			and (
				active == nil
				or (fsm.last_spin_serial or 0) > (active.fsm.last_spin_serial or 0)
				or (
					(fsm.last_spin_serial or 0) == (active.fsm.last_spin_serial or 0)
					and (fsm.id or 0) > (active.fsm.id or 0)
				)
			)
		then
			active = {
				config = intent,
				id = intent_id,
				fsm = fsm,
			}
		end
	end

	return by_intent, active
end

function M:decision_graph(raw)
	local endpoint_config = self.config.endpoint or {}
	local endpoint_fsm = latest_fsm_by_source(raw, endpoint_config.source)
	local current_state = endpoint_config.initial or self.config.initial_state or "idle"
	local active_nodes = {}
	local active_edges = {}
	local active_status = {}

	if type(endpoint_fsm) == "table" and endpoint_fsm.current_state ~= nil then
		current_state = tostring(endpoint_fsm.current_state)
	end

	local state_node = endpoint_node_id(current_state)
	active_nodes[#active_nodes + 1] = state_node

	if
		type(endpoint_fsm) == "table"
		and type(endpoint_fsm.last_transition) == "table"
		and endpoint_fsm.last_transition.to == current_state
		and endpoint_fsm.last_transition.from ~= current_state
	then
		active_edges[#active_edges + 1] =
			graph_edge_id(endpoint_node_id(endpoint_fsm.last_transition.from), state_node)
	end

	local _, active_intent = self:intent_runtime(raw)
	local current_intent = nil
	local current_phase = "none"

	if active_intent ~= nil then
		current_intent = active_intent.id
		current_phase = tostring(active_intent.fsm.current_state or "none")

		local intent_id = intent_node_id(active_intent.id)
		local configured_endpoint = active_intent.config.endpoint or current_state
		local parent_endpoint_id = resolve_endpoint_ref(self.config, configured_endpoint)
		local status = phase_status(self.failed_latch[active_intent.id], current_phase)

		active_nodes[#active_nodes + 1] = intent_id
		active_edges[#active_edges + 1] = graph_edge_id(parent_endpoint_id, intent_id)
		active_status[intent_id] = status

		local phase = current_phase
		if is_result_phase(phase) then
			phase = self.last_non_result_phase[active_intent.id]
			if
				phase == nil
				and type(active_intent.fsm.last_state) == "string"
				and not is_result_phase(active_intent.fsm.last_state)
			then
				phase = active_intent.fsm.last_state
			end
		end

		if type(phase) == "string" and phase ~= "" and not is_result_phase(phase) then
			local phase_id = phase_node_id(active_intent.id, phase)
			active_nodes[#active_nodes + 1] = phase_id
			active_edges[#active_edges + 1] = graph_edge_id(intent_id, phase_id)
			active_status[phase_id] = status
		end
	end

	return {
		id = self.config.id or "decision",
		label = self.config.label or "Decision Graph",
		nodes = self.nodes,
		edges = self.edges,
		active_nodes = active_nodes,
		active_edges = active_edges,
		active_status = active_status,
		failures = self.failures,
		current_state = current_state,
		current_intent = current_intent,
		current_phase = current_phase,
		revision = self.revision,
		updated_at = now(),
	}
end

function M:snapshot()
	local raw = self.loot_probe.snapshot()
	for _, fsm in ipairs(fsm_items(raw)) do
		local declared_edges = declared_edges_for_fsm(self.config, fsm)
		if next(declared_edges) ~= nil then
			fsm.declared_edges = declared_edges
		end
	end
	raw.decision_graph = self:decision_graph(raw)
	return raw
end

return M
