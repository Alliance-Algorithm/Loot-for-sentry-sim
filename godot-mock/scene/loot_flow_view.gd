extends Control

signal edge_selected(edge: Dictionary)

const PANEL_BG := Color(0.045, 0.055, 0.065, 0.96)
const PANEL_BORDER := Color(0.22, 0.26, 0.30, 0.95)
const FSM_TITLE := Color(0.72, 0.80, 0.88, 1.0)
const TEXT_COLOR := Color(0.88, 0.92, 0.96, 1.0)
const MUTED_TEXT := Color(0.48, 0.56, 0.64, 1.0)
const NODE_BG := Color(0.10, 0.12, 0.14, 1.0)
const NODE_BORDER := Color(0.40, 0.48, 0.56, 1.0)
const CURRENT_BG := Color(0.05, 0.42, 0.34, 1.0)
const CURRENT_BORDER := Color(0.20, 0.95, 0.74, 1.0)
const FAILED_BG := Color(0.42, 0.07, 0.06, 1.0)
const FAILED_BORDER := Color(1.0, 0.25, 0.18, 1.0)
const HOLD_BG := Color(0.05, 0.25, 0.50, 1.0)
const HOLD_BORDER := Color(0.22, 0.62, 1.0, 1.0)
const LAST_FROM_BORDER := Color(0.95, 0.78, 0.18, 1.0)
const DECLARED_EDGE_COLOR := Color(0.40, 0.46, 0.52, 0.42)
const OBSERVED_EDGE_COLOR := Color(0.52, 0.62, 0.72, 0.90)
const UNDECLARED_EDGE_COLOR := Color(0.95, 0.58, 0.18, 0.92)
const LAST_EDGE_COLOR := Color(0.18, 0.78, 1.0, 1.0)
const SELECTED_EDGE_COLOR := Color(0.80, 0.58, 1.0, 1.0)
const SELF_EDGE_COLOR := Color(1.0, 0.58, 0.18, 0.92)

const NODE_SIZE := Vector2(126.0, 42.0)
const DECISION_NODE_SIZE := Vector2(168.0, 40.0)
const NODE_GAP := 54.0
const NODE_ROW_GAP := 42.0
const DECISION_COLUMN_GAP := 280.0
const DECISION_ROW_GAP := 50.0
const FSM_GAP := 120.0
const MARGIN := 28.0
const TITLE_HEIGHT := 24.0
const FAILURE_PANEL_SIZE := Vector2(260.0, 108.0)
const FAILURE_PANEL_PADDING := 10.0
const EMPTY_TEXT := "Waiting for loot.snapshot"

var loot_state: Dictionary = {}
var graphs: Dictionary = {}
var edge_hitboxes: Array = []
var selected_edge_key: String = ""


func _ready() -> void:
	custom_minimum_size = Vector2(720.0, 480.0)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_minimum_size()
		queue_redraw()


func update_loot(next_state: Dictionary) -> void:
	loot_state = next_state.duplicate(true)

	var fsm_root: Dictionary = _dict(loot_state.get("fsm", {}))
	for raw_item in _array(fsm_root.get("items", [])):
		if typeof(raw_item) != TYPE_DICTIONARY:
			continue
		_update_fsm(raw_item as Dictionary)

	_update_minimum_size()
	queue_redraw()


func reset() -> void:
	loot_state = {}
	graphs.clear()
	edge_hitboxes.clear()
	selected_edge_key = ""
	_update_minimum_size()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return

	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	for index in range(edge_hitboxes.size() - 1, -1, -1):
		var hitbox: Dictionary = edge_hitboxes[index]
		var rect: Rect2 = hitbox["rect"]
		if rect.has_point(mouse_event.position):
			selected_edge_key = str(hitbox["key"])
			emit_signal("edge_selected", hitbox["edge"])
			queue_redraw()
			accept_event()
			return

	selected_edge_key = ""
	emit_signal("edge_selected", {})
	queue_redraw()


func _update_fsm(fsm: Dictionary) -> void:
	var id: String = str(fsm.get("id", "unknown"))
	if not graphs.has(id):
		graphs[id] = {
			"id": id,
			"label": str(fsm.get("label", "fsm#%s" % id)),
			"states": {},
			"edges": {},
			"current_state": "",
			"last_state": "",
			"last_transition": {},
			"last_transition_mark": "",
		}

	var graph: Dictionary = graphs[id]
	graph["label"] = str(fsm.get("label", graph.get("label", "fsm#%s" % id)))
	graph["current_state"] = _state_name(fsm.get("current_state", ""))
	graph["last_state"] = _state_name(fsm.get("last_state", ""))
	graph["last_transition"] = _dict(fsm.get("last_transition", {}))
	var transition_count: int = int(fsm.get("transition_count", 0))

	var states: Dictionary = graph["states"]
	for state_name in _array(fsm.get("states", [])):
		states[str(state_name)] = true
	if graph["current_state"] != "":
		states[graph["current_state"]] = true
	if graph["last_state"] != "":
		states[graph["last_state"]] = true

	var declared_edges: Array = _array(fsm.get("declared_edges", []))
	_sync_declared_edges(graph, declared_edges)

	var observed_edges: Array = _array(fsm.get("observed_edges", []))
	if not observed_edges.is_empty():
		_sync_observed_edges(graph, observed_edges)
		return

	var transition: Dictionary = graph["last_transition"]
	var from_state: String = _state_name(transition.get("from", ""))
	var to_state: String = _state_name(transition.get("to", ""))
	if from_state != "" and to_state != "":
		states[from_state] = true
		states[to_state] = true
		var edge_key: String = _edge_key(from_state, to_state)
		var transition_time: float = float(transition.get("time", 0.0))
		var transition_mark: String = "%d|%s|%.6f" % [transition_count, edge_key, transition_time]
		if str(graph.get("last_transition_mark", "")) == transition_mark:
			return
		graph["last_transition_mark"] = transition_mark

		var edges: Dictionary = graph["edges"]
		if not edges.has(edge_key):
			edges[edge_key] = {
				"from": from_state,
				"to": to_state,
				"declared": false,
				"observed": true,
				"count": 0,
				"last_time": 0.0,
			}
		var edge: Dictionary = edges[edge_key]
		edge["observed"] = true
		if transition_time >= float(edge.get("last_time", -1.0)):
			edge["last_time"] = transition_time
			edge["count"] = int(edge.get("count", 0)) + 1


func _sync_declared_edges(graph: Dictionary, declared_edges: Array) -> void:
	var edges: Dictionary = graph["edges"]
	var states: Dictionary = graph["states"]
	for key in edges.keys():
		var edge: Dictionary = edges[key]
		edge["declared"] = false
		edge["label"] = null
		edge["declared_source"] = null
		edge["declared_line"] = null

	for raw_edge in declared_edges:
		if typeof(raw_edge) != TYPE_DICTIONARY:
			continue

		var edge_data: Dictionary = raw_edge as Dictionary
		var from_state: String = _state_name(edge_data.get("from", ""))
		var to_state: String = _state_name(edge_data.get("to", ""))
		if from_state == "" or to_state == "":
			continue

		states[from_state] = true
		states[to_state] = true
		var key: String = _edge_key(from_state, to_state)
		if not edges.has(key):
			edges[key] = {
				"from": from_state,
				"to": to_state,
				"count": 0,
				"last_time": 0.0,
				"observed": false,
			}
		var edge: Dictionary = edges[key]
		edge["declared"] = true
		edge["label"] = edge_data.get("label", null)
		edge["declared_source"] = edge_data.get("source", null)
		edge["declared_line"] = edge_data.get("line", null)


func _sync_observed_edges(graph: Dictionary, observed_edges: Array) -> void:
	var edges: Dictionary = graph["edges"]
	var states: Dictionary = graph["states"]
	for key in edges.keys():
		var edge: Dictionary = edges[key]
		edge["observed"] = false
		edge["count"] = 0
		edge["last_time"] = 0.0
		edge["last_reason"] = null
		edge["source"] = null
		edge["line"] = null
	for raw_edge in observed_edges:
		if typeof(raw_edge) != TYPE_DICTIONARY:
			continue

		var edge_data: Dictionary = raw_edge as Dictionary
		var from_state: String = _state_name(edge_data.get("from", ""))
		var to_state: String = _state_name(edge_data.get("to", ""))
		if from_state == "" or to_state == "":
			continue

		states[from_state] = true
		states[to_state] = true
		var key: String = _edge_key(from_state, to_state)
		if not edges.has(key):
			edges[key] = {
				"from": from_state,
				"to": to_state,
				"declared": false,
			}
		var edge: Dictionary = edges[key]
		edge["observed"] = true
		edge["count"] = int(edge_data.get("count", 0))
		edge["last_time"] = float(edge_data.get("last_time", 0.0))
		edge["last_reason"] = edge_data.get("last_reason", null)
		edge["source"] = edge_data.get("source", null)
		edge["line"] = edge_data.get("line", null)


func _register_edge_hitbox(
	key: String,
	edge: Dictionary,
	from_rect: Rect2,
	to_rect: Rect2
) -> void:
	var hit_rect: Rect2
	if from_rect == to_rect:
		hit_rect = Rect2(
			from_rect.position + Vector2(from_rect.size.x * 0.5 - 24.0, -36.0),
			Vector2(48.0, 46.0)
		)
	else:
		var from_center: Vector2 = from_rect.get_center()
		var to_center: Vector2 = to_rect.get_center()
		var start: Vector2 = Vector2(from_rect.position.x + from_rect.size.x, from_center.y)
		var finish: Vector2 = Vector2(to_rect.position.x, to_center.y)
		if to_center.x < from_center.x:
			start = Vector2(from_rect.position.x, from_center.y)
			finish = Vector2(to_rect.position.x + to_rect.size.x, to_center.y)
		var min_point: Vector2 = Vector2(minf(start.x, finish.x), minf(start.y, finish.y))
		var max_point: Vector2 = Vector2(maxf(start.x, finish.x), maxf(start.y, finish.y))
		hit_rect = Rect2(min_point, max_point - min_point).grow(10.0)

	var selected_edge: Dictionary = edge.duplicate(true)
	selected_edge["key"] = key
	edge_hitboxes.append({
		"key": key,
		"rect": hit_rect,
		"edge": selected_edge,
	})


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(rect, PANEL_BG, true)
	draw_rect(rect, PANEL_BORDER, false, 1.0)

	var font: Font = get_theme_default_font()
	var font_size: int = get_theme_default_font_size()
	edge_hitboxes.clear()

	if _has_decision_graph():
		_draw_decision_graph(_decision_graph(), font, font_size)
		return

	if graphs.is_empty():
		_draw_empty()
		return

	var graph_ids: Array = graphs.keys()
	graph_ids.sort_custom(func(a, b): return str(a) < str(b))

	var y: float = MARGIN
	for id in graph_ids:
		var graph: Dictionary = graphs[id]
		var state_names: Array = _state_names(graph)
		var row_height: float = _fsm_row_height(state_names.size())
		_draw_fsm(graph, state_names, Vector2(MARGIN, y), row_height, font, font_size)
		y += row_height + FSM_GAP


func _draw_empty() -> void:
	var font: Font = get_theme_default_font()
	var font_size: int = get_theme_default_font_size()
	var text_size: Vector2 = font.get_string_size(
		EMPTY_TEXT,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size
	)
	var pos: Vector2 = (size - text_size) * 0.5
	draw_string(font, pos, EMPTY_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, MUTED_TEXT)


func _draw_decision_graph(graph: Dictionary, font: Font, font_size: int) -> void:
	var nodes: Array = _array(graph.get("nodes", []))
	var edges: Array = _array(graph.get("edges", []))
	if nodes.is_empty():
		_draw_empty()
		return

	var current_state: String = str(graph.get("current_state", ""))
	var current_intent: String = str(graph.get("current_intent", ""))
	var current_phase: String = str(graph.get("current_phase", ""))
	var title: String = "%s  state=%s  intent=%s  phase=%s" % [
		str(graph.get("label", "Decision Graph")),
		current_state,
		current_intent,
		current_phase,
	]
	draw_string(
		font,
		Vector2(MARGIN, MARGIN + font_size),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		FSM_TITLE
	)

	var origin: Vector2 = Vector2(MARGIN, MARGIN + TITLE_HEIGHT + 20.0)
	var node_positions: Dictionary = _decision_node_positions(nodes, origin)
	var active_nodes: Dictionary = _string_set(_array(graph.get("active_nodes", [])))
	var active_edges: Dictionary = _string_set(_array(graph.get("active_edges", [])))
	var active_status: Dictionary = _dict(graph.get("active_status", {}))

	_draw_decision_edges(edges, node_positions, active_edges, font, maxi(9, font_size - 2))
	_draw_decision_nodes(nodes, node_positions, active_nodes, active_status, font, font_size)
	_draw_failure_panel(graph, font, maxi(9, font_size - 2))


func _draw_decision_edges(
	edges: Array,
	node_positions: Dictionary,
	active_edges: Dictionary,
	font: Font,
	font_size: int
) -> void:
	for raw_edge in edges:
		if typeof(raw_edge) != TYPE_DICTIONARY:
			continue

		var edge: Dictionary = raw_edge as Dictionary
		var from_id: String = str(edge.get("from", ""))
		var to_id: String = str(edge.get("to", ""))
		if not node_positions.has(from_id) or not node_positions.has(to_id):
			continue

		var edge_id: String = str(edge.get("id", _edge_key(from_id, to_id)))
		var scoped_key: String = "decision|%s" % edge_id
		var from_rect: Rect2 = node_positions[from_id]
		var to_rect: Rect2 = node_positions[to_id]
		var is_active: bool = bool(active_edges.get(edge_id, false))
		var is_selected: bool = scoped_key == selected_edge_key
		var color: Color = DECLARED_EDGE_COLOR
		var width: float = 1.2
		if is_active:
			color = LAST_EDGE_COLOR
			width = 3.2
		if is_selected:
			color = SELECTED_EDGE_COLOR
			width = 4.0

		var selected_edge: Dictionary = edge.duplicate(true)
		selected_edge["graph_id"] = "decision"
		selected_edge["active"] = is_active
		selected_edge["kind"] = "decision_edge"
		_register_edge_hitbox(scoped_key, selected_edge, from_rect, to_rect)
		_draw_edge_line(from_rect, to_rect, color, width)

		if is_active or is_selected:
			_draw_edge_label(from_rect, to_rect, str(edge.get("label", "")), color, font, font_size)


func _draw_decision_nodes(
	nodes: Array,
	node_positions: Dictionary,
	active_nodes: Dictionary,
	active_status: Dictionary,
	font: Font,
	font_size: int
) -> void:
	for raw_node in nodes:
		if typeof(raw_node) != TYPE_DICTIONARY:
			continue

		var node: Dictionary = raw_node as Dictionary
		var node_id: String = str(node.get("id", ""))
		if not node_positions.has(node_id):
			continue

		var node_rect: Rect2 = node_positions[node_id]
		var kind: String = str(node.get("kind", "node"))
		var is_active: bool = bool(active_nodes.get(node_id, false))
		var status: String = str(active_status.get(node_id, "active"))
		var fill: Color = _decision_node_fill(kind, is_active, status)
		var border: Color = NODE_BORDER
		var text_color: Color = TEXT_COLOR
		if is_active:
			border = _decision_node_border(status)
		elif kind == "phase":
			text_color = Color(0.70, 0.76, 0.82, 1.0)

		draw_rect(node_rect, fill, true)
		draw_rect(node_rect, border, false, 2.0)
		_draw_centered_label(node_rect, str(node.get("label", node_id)), font, font_size, text_color)


func _draw_failure_panel(graph: Dictionary, font: Font, font_size: int) -> void:
	var failures: Array = _array(graph.get("failures", []))
	if failures.is_empty():
		return

	var panel_rect: Rect2 = Rect2(
		Vector2(MARGIN, maxf(MARGIN, size.y - MARGIN - FAILURE_PANEL_SIZE.y)),
		FAILURE_PANEL_SIZE
	)
	draw_rect(panel_rect, PANEL_BG, true)
	draw_rect(panel_rect, FAILED_BORDER, false, 1.2)

	var x: float = panel_rect.position.x + FAILURE_PANEL_PADDING
	var y: float = panel_rect.position.y + FAILURE_PANEL_PADDING + float(font_size)
	draw_string(font, Vector2(x, y), "Failures", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, FAILED_BORDER)
	y += float(font_size) + 6.0

	var start_index: int = maxi(0, failures.size() - 3)
	for index in range(start_index, failures.size()):
		var failure: Dictionary = _dict(failures[index])
		var intent: String = str(failure.get("intent", "unknown"))
		var task: String = str(failure.get("task", "unknown"))
		var line: String = "%s / %s" % [intent, task]
		draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, TEXT_COLOR)
		y += float(font_size) + 4.0


func _draw_edge_label(
	from_rect: Rect2,
	to_rect: Rect2,
	label: String,
	color: Color,
	font: Font,
	font_size: int
) -> void:
	if label == "":
		return

	var mid: Vector2 = (from_rect.get_center() + to_rect.get_center()) * 0.5 + Vector2(0.0, -12.0)
	var text_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var label_rect: Rect2 = Rect2(
		mid - Vector2(text_size.x * 0.5 + 6.0, text_size.y * 0.5 + 4.0),
		text_size + Vector2(12.0, 8.0)
	)
	draw_rect(label_rect, PANEL_BG, true)
	draw_rect(label_rect, color, false, 1.0)
	draw_string(
		font,
		label_rect.position + Vector2(6.0, label_rect.size.y - 7.0),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		color
	)


func _draw_fsm(
	graph: Dictionary,
	state_names: Array,
	origin: Vector2,
	_row_height: float,
	font: Font,
	font_size: int
) -> void:
	var title: String = "%s  current=%s" % [
		str(graph.get("label", graph.get("id", "fsm"))),
		str(graph.get("current_state", "")),
	]
	draw_string(font, origin + Vector2(0.0, font_size), title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, FSM_TITLE)

	var lane_top: float = origin.y + TITLE_HEIGHT + 18.0
	var node_positions: Dictionary = _node_positions(state_names, Vector2(origin.x, lane_top))
	_draw_edges(graph, node_positions)
	_draw_nodes(graph, state_names, node_positions, font, font_size)


func _draw_edges(graph: Dictionary, node_positions: Dictionary) -> void:
	var edges: Dictionary = graph.get("edges", {})
	var last_transition: Dictionary = graph.get("last_transition", {})
	var last_key: String = _edge_key(
		_state_name(last_transition.get("from", "")),
		_state_name(last_transition.get("to", ""))
	)
	var edge_keys: Array = edges.keys()
	edge_keys.sort()

	for raw_key in edge_keys:
		var key: String = str(raw_key)
		var edge: Dictionary = edges[key]
		var from_state: String = str(edge.get("from", ""))
		var to_state: String = str(edge.get("to", ""))
		if not node_positions.has(from_state) or not node_positions.has(to_state):
			continue

		var from_rect: Rect2 = node_positions[from_state]
		var to_rect: Rect2 = node_positions[to_state]
		var is_last: bool = key == last_key
		var is_declared: bool = bool(edge.get("declared", false))
		var is_observed: bool = bool(edge.get("observed", false))
		var scoped_key: String = "%s|%s" % [str(graph.get("id", "")), key]
		var is_selected: bool = scoped_key == selected_edge_key
		var color: Color = UNDECLARED_EDGE_COLOR
		var width: float = 1.8
		if is_declared:
			color = DECLARED_EDGE_COLOR
			if not is_observed:
				width = 1.2
		if is_observed:
			color = OBSERVED_EDGE_COLOR
		if is_last:
			color = LAST_EDGE_COLOR
			width = 3.0
		if is_selected:
			color = SELECTED_EDGE_COLOR
			width = 4.0
		_register_edge_hitbox(scoped_key, edge, from_rect, to_rect)

		if from_state == to_state:
			if is_observed and not is_last:
				color = SELF_EDGE_COLOR
			_draw_self_edge(from_rect, color, width)
		else:
			_draw_edge_line(from_rect, to_rect, color, width)

		var count: int = int(edge.get("count", 0))
		if count > 1:
			var mid: Vector2 = (
				(from_rect.get_center() + to_rect.get_center()) * 0.5 + Vector2(0.0, -14.0)
			)
			draw_string(
				get_theme_default_font(),
				mid,
				"x%d" % count,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1.0,
				get_theme_default_font_size() - 1,
				color
			)


func _draw_edge_line(from_rect: Rect2, to_rect: Rect2, color: Color, width: float) -> void:
	var from_center: Vector2 = from_rect.get_center()
	var to_center: Vector2 = to_rect.get_center()
	if absf(from_center.x - to_center.x) <= 1.0 and absf(from_center.y - to_center.y) > 1.0:
		_draw_same_column_edge(from_rect, to_rect, color, width)
		return

	var start: Vector2 = Vector2(from_rect.position.x + from_rect.size.x, from_center.y)
	var finish: Vector2 = Vector2(to_rect.position.x, to_center.y)
	if to_center.x < from_center.x:
		start = Vector2(from_rect.position.x, from_center.y)
		finish = Vector2(to_rect.position.x + to_rect.size.x, to_center.y)

	var delta: Vector2 = finish - start
	if delta.length() <= 1.0:
		return
	var direction: Vector2 = delta.normalized()
	var arrow_base: Vector2 = finish - direction * 10.0
	var normal: Vector2 = Vector2(-direction.y, direction.x)
	draw_line(start, finish, color, width, true)
	draw_colored_polygon(PackedVector2Array([
		finish,
		arrow_base + normal * 4.5,
		arrow_base - normal * 4.5,
	]), color)


func _draw_same_column_edge(from_rect: Rect2, to_rect: Rect2, color: Color, width: float) -> void:
	var from_center: Vector2 = from_rect.get_center()
	var to_center: Vector2 = to_rect.get_center()
	var start: Vector2 = Vector2(from_center.x, from_rect.position.y + from_rect.size.y)
	var finish: Vector2 = Vector2(to_center.x, to_rect.position.y)
	if to_center.y < from_center.y:
		start = Vector2(from_center.x, from_rect.position.y)
		finish = Vector2(to_center.x, to_rect.position.y + to_rect.size.y)

	var delta: Vector2 = finish - start
	if delta.length() <= 1.0:
		return
	var direction: Vector2 = delta.normalized()
	var arrow_base: Vector2 = finish - direction * 10.0
	var normal: Vector2 = Vector2(-direction.y, direction.x)
	draw_line(start, finish, color, width, true)
	draw_colored_polygon(PackedVector2Array([
		finish,
		arrow_base + normal * 4.5,
		arrow_base - normal * 4.5,
	]), color)


func _draw_self_edge(rect: Rect2, color: Color, width: float) -> void:
	var center: Vector2 = rect.position + Vector2(rect.size.x * 0.5, -10.0)
	draw_arc(center, 18.0, PI * 0.10, PI * 1.85, 24, color, width, true)
	var arrow_tip: Vector2 = rect.position + Vector2(rect.size.x * 0.70, 0.0)
	draw_colored_polygon(PackedVector2Array([
		arrow_tip,
		arrow_tip + Vector2(-8.0, -6.0),
		arrow_tip + Vector2(2.0, -10.0),
	]), color)


func _draw_nodes(
	graph: Dictionary,
	state_names: Array,
	node_positions: Dictionary,
	font: Font,
	font_size: int
) -> void:
	var current_state: String = str(graph.get("current_state", ""))
	var last_transition: Dictionary = graph.get("last_transition", {})
	var last_from: String = _state_name(last_transition.get("from", ""))

	for state_name in state_names:
		var node_rect: Rect2 = node_positions[state_name]
		var is_current: bool = str(state_name) == current_state
		var is_last_from: bool = str(state_name) == last_from
		var fill: Color = NODE_BG
		var border: Color = NODE_BORDER
		if is_current:
			fill = CURRENT_BG
			border = CURRENT_BORDER
		if is_last_from and not is_current:
			border = LAST_FROM_BORDER

		draw_rect(node_rect, fill, true)
		draw_rect(node_rect, border, false, 2.0)
		_draw_centered_label(node_rect, str(state_name), font, font_size, TEXT_COLOR)


func _draw_centered_label(rect: Rect2, text: String, font: Font, font_size: int, color: Color) -> void:
	var fitted_size: int = font_size
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fitted_size)
	while text_size.x > rect.size.x - 12.0 and fitted_size > 9:
		fitted_size -= 1
		text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fitted_size)
	var pos: Vector2 = rect.position + Vector2(
		(rect.size.x - text_size.x) * 0.5,
		(rect.size.y + text_size.y) * 0.5 - 4.0
	)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fitted_size, color)


func _state_names(graph: Dictionary) -> Array:
	var states: Dictionary = graph.get("states", {})
	var names: Array = states.keys()
	names.sort_custom(func(a, b): return str(a) < str(b))
	return names


func _decision_node_positions(nodes: Array, origin: Vector2) -> Dictionary:
	var rows_by_level: Dictionary = {}
	var levels: Array = []
	for raw_node in nodes:
		if typeof(raw_node) != TYPE_DICTIONARY:
			continue

		var node: Dictionary = raw_node as Dictionary
		var node_id: String = str(node.get("id", ""))
		if node_id == "":
			continue

		var level: int = int(node.get("level", 0))
		var level_key: String = str(level)
		if not rows_by_level.has(level_key):
			rows_by_level[level_key] = []
			levels.append(level)

		var row: Array = rows_by_level[level_key]
		row.append(node_id)

	levels.sort()

	var result: Dictionary = {}
	for raw_level in levels:
		var level: int = int(raw_level)
		var row_ids: Array = rows_by_level[str(level)]
		for row_index in range(row_ids.size()):
			var id: String = str(row_ids[row_index])
			result[id] = Rect2(
				origin + Vector2(
					float(level) * (DECISION_NODE_SIZE.x + DECISION_COLUMN_GAP),
					float(row_index) * (DECISION_NODE_SIZE.y + DECISION_ROW_GAP)
				),
				DECISION_NODE_SIZE
			)
	return result


func _node_positions(state_names: Array, origin: Vector2) -> Dictionary:
	var result: Dictionary = {}
	var x: float = origin.x
	var y: float = origin.y
	var max_x: float = origin.x + maxf(size.x - MARGIN * 2.0, NODE_SIZE.x)
	for state_name in state_names:
		if x > origin.x and x + NODE_SIZE.x > max_x:
			x = origin.x
			y += NODE_SIZE.y + NODE_ROW_GAP
		result[str(state_name)] = Rect2(Vector2(x, y), NODE_SIZE)
		x += NODE_SIZE.x + NODE_GAP
	return result


func _fsm_row_height(state_count: int) -> float:
	var width_per_state: float = NODE_SIZE.x + NODE_GAP
	var available_width: float = maxf(size.x - MARGIN * 2.0, width_per_state)
	var columns: int = maxi(1, int(floor((available_width + NODE_GAP) / width_per_state)))
	var rows: int = maxi(1, int(ceil(float(maxi(state_count, 1)) / float(columns))))
	return TITLE_HEIGHT + 18.0 + float(rows) * NODE_SIZE.y + float(rows - 1) * NODE_ROW_GAP


func _content_height() -> float:
	if _has_decision_graph():
		return _decision_content_height()

	if graphs.is_empty():
		return 480.0

	var graph_ids: Array = graphs.keys()
	graph_ids.sort_custom(func(a, b): return str(a) < str(b))
	var height: float = MARGIN
	for id in graph_ids:
		var graph: Dictionary = graphs[id]
		height += _fsm_row_height(_state_names(graph).size()) + FSM_GAP
	return maxf(480.0, height + MARGIN - FSM_GAP)


func _content_width() -> float:
	if _has_decision_graph():
		return _decision_content_width()
	return 720.0


func _decision_content_height() -> float:
	var nodes: Array = _array(_decision_graph().get("nodes", []))
	var rows_by_level: Dictionary = {}
	var max_rows: int = 1
	for raw_node in nodes:
		if typeof(raw_node) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = raw_node as Dictionary
		var level_key: String = str(int(node.get("level", 0)))
		rows_by_level[level_key] = int(rows_by_level.get(level_key, 0)) + 1
		max_rows = maxi(max_rows, int(rows_by_level[level_key]))

	var graph_top: float = MARGIN + TITLE_HEIGHT + 20.0
	var body_height: float = (
		float(max_rows) * DECISION_NODE_SIZE.y
		+ float(maxi(0, max_rows - 1)) * DECISION_ROW_GAP
	)
	return maxf(480.0, graph_top + body_height + MARGIN)


func _decision_content_width() -> float:
	var nodes: Array = _array(_decision_graph().get("nodes", []))
	var max_level: int = 0
	for raw_node in nodes:
		if typeof(raw_node) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = raw_node as Dictionary
		max_level = maxi(max_level, int(node.get("level", 0)))

	var graph_width: float = (
		MARGIN * 2.0
		+ float(max_level + 1) * DECISION_NODE_SIZE.x
		+ float(max_level) * DECISION_COLUMN_GAP
	)
	return maxf(720.0, graph_width)


func _update_minimum_size() -> void:
	custom_minimum_size = Vector2(_content_width(), _content_height())


func _edge_key(from_state: String, to_state: String) -> String:
	return "%s -> %s" % [from_state, to_state]


func _has_decision_graph() -> bool:
	var graph: Dictionary = _decision_graph()
	return not _array(graph.get("nodes", [])).is_empty()


func _decision_graph() -> Dictionary:
	return _dict(loot_state.get("decision_graph", {}))


func _string_set(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for value in values:
		result[str(value)] = true
	return result


func _decision_node_fill(kind: String, active: bool, status: String) -> Color:
	if active:
		if status == "failed":
			return FAILED_BG
		if status == "hold":
			return HOLD_BG
		return CURRENT_BG
	if kind == "root":
		return Color(0.13, 0.13, 0.12, 1.0)
	if kind == "endpoint":
		return Color(0.10, 0.14, 0.17, 1.0)
	if kind == "intent":
		return Color(0.13, 0.12, 0.17, 1.0)
	if kind == "phase":
		return Color(0.08, 0.10, 0.12, 1.0)
	return NODE_BG


func _decision_node_border(status: String) -> Color:
	if status == "failed":
		return FAILED_BORDER
	if status == "hold":
		return HOLD_BORDER
	return CURRENT_BORDER


func _dict(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _state_name(value: Variant) -> String:
	if value == null:
		return ""
	return str(value)
