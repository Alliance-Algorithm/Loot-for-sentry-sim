extends Node3D

const OVERLAY_Y := 0.08
const POINT_RADIUS := 0.12
const TARGET_RADIUS := 0.18
const MAX_HISTORY_POINTS := 32

var robot: Node3D
var target_point: Node3D
var nav_agent: NavigationAgent3D
var loot_state: Dictionary = {}
var current_target: Variant = null
var nav_history: Array = []

var route_mesh_instance: MeshInstance3D
var target_marker: MeshInstance3D
var history_root: Node3D
var nodes_ready := false


func setup(robot_node: Node3D, target_node: Node3D) -> void:
	robot = robot_node
	target_point = target_node
	nav_agent = robot.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	_build_nodes()


func _ready() -> void:
	if not nodes_ready:
		_build_nodes()
	_refresh_overlay()


func update_loot(next_state: Dictionary) -> void:
	loot_state = next_state.duplicate(true)
	var actions: Dictionary = _dict(loot_state.get("actions", {}))
	current_target = actions.get("nav_target", null)
	var raw_history = actions.get("nav_history", [])
	if typeof(raw_history) == TYPE_ARRAY:
		nav_history = raw_history.duplicate(true)
		while nav_history.size() > MAX_HISTORY_POINTS:
			nav_history.pop_front()
	if not is_inside_tree() or not nodes_ready:
		return
	_refresh_overlay()


func _process(_delta: float) -> void:
	if not nodes_ready:
		return
	_refresh_dynamic_positions()


func _build_nodes() -> void:
	if nodes_ready:
		return
	route_mesh_instance = MeshInstance3D.new()
	route_mesh_instance.name = "LootRoute"
	add_child(route_mesh_instance)

	target_marker = MeshInstance3D.new()
	target_marker.name = "LootTarget"
	var target_mesh := SphereMesh.new()
	target_mesh.radius = TARGET_RADIUS
	target_mesh.height = TARGET_RADIUS * 2.0
	target_marker.mesh = target_mesh
	target_marker.material_override = _material(Color(0.1, 0.78, 1.0, 0.72))
	add_child(target_marker)

	history_root = Node3D.new()
	history_root.name = "LootHistory"
	add_child(history_root)

	nodes_ready = true


func _refresh_overlay() -> void:
	if not is_inside_tree() or not nodes_ready:
		return
	_rebuild_history_markers()
	_rebuild_route_mesh()
	_refresh_dynamic_positions()


func _refresh_dynamic_positions() -> void:
	if current_target != null and typeof(current_target) == TYPE_DICTIONARY:
		target_marker.visible = true
		target_marker.global_position = _point_to_world(current_target as Dictionary)
	elif target_point != null:
		target_marker.visible = true
		target_marker.global_position = target_point.global_position + Vector3(0.0, OVERLAY_Y, 0.0)
	else:
		target_marker.visible = false

	_rebuild_route_mesh()


func _rebuild_history_markers() -> void:
	for child in history_root.get_children():
		child.queue_free()

	for index in nav_history.size():
		var point = nav_history[index]
		if typeof(point) != TYPE_DICTIONARY:
			continue

		var marker := MeshInstance3D.new()
		marker.name = "LootHistoryPoint%d" % index
		var mesh := SphereMesh.new()
		mesh.radius = POINT_RADIUS
		mesh.height = POINT_RADIUS * 2.0
		marker.mesh = mesh
		marker.material_override = _material(Color(0.95, 0.83, 0.16, 0.62))
		marker.position = _point_to_world(point as Dictionary)
		history_root.add_child(marker)


func _rebuild_route_mesh() -> void:
	var points := _navigation_path_points()

	if points.size() < 2:
		route_mesh_instance.mesh = null
		return

	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in points:
		mesh.surface_set_color(Color(0.1, 0.78, 1.0, 0.92))
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	route_mesh_instance.mesh = mesh


func _navigation_path_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	if nav_agent == null and robot != null:
		nav_agent = robot.get_node_or_null("NavigationAgent3D") as NavigationAgent3D

	if nav_agent != null:
		var path := nav_agent.get_current_navigation_path()
		for point in path:
			var raised := point
			raised.y += OVERLAY_Y
			points.append(raised)

	if points.size() >= 2:
		return points

	if robot != null:
		points.append(robot.global_position + Vector3(0.0, OVERLAY_Y, 0.0))

	if current_target != null and typeof(current_target) == TYPE_DICTIONARY:
		points.append(_point_to_world(current_target as Dictionary))
	elif target_point != null:
		points.append(target_point.global_position + Vector3(0.0, OVERLAY_Y, 0.0))

	return points


func _point_to_world(point: Dictionary) -> Vector3:
	return Vector3(
		float(point.get("y", 0.0)),
		OVERLAY_Y,
		float(point.get("x", 0.0))
	)


func _dict(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value
	return {}


func _array(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	return []


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.7
	return material
