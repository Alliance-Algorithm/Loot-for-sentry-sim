extends Node3D
## 通用比赛建筑目标：基地 / 前哨站。
## 半透明立方体，可被 enemy 子弹命中；头顶显示血条和数值。

@export_enum("outpost", "base") var structure_kind := "outpost"
@export var max_health := 1500
@export var team := "ally"
@export var cube_size := Vector3(1.4, 1.4, 1.4)
@export var hitbox_size := Vector3(1.5, 1.5, 1.5)
@export var display_height := 0.5

const ARMOR_LAYER := 1 << 5
const HEALTH_BAR_BACK_SIZE := Vector2(1.5, 0.16)
const HEALTH_BAR_FILL_SIZE := Vector2(1.4, 0.12)
const HEALTH_BAR_BACK_PRIORITY := 10
const HEALTH_BAR_FILL_PRIORITY := 11
const HEALTH_BAR_FILL_Z_OFFSET := -0.02
const HITBOX_SCRIPT := preload("res://scene/sim_structure_hitbox.gd")

var body_mesh: MeshInstance3D = null
var hitbox_area: Area3D = null
var health_bar_anchor: Node3D = null
var health_bar_back: MeshInstance3D = null
var health_bar_fill: MeshInstance3D = null
var hp_label: Label3D = null


func _ready() -> void:
	_setup_body_mesh()
	_setup_hitbox()
	_setup_health_display()
	_refresh_health_display()


func _process(_delta: float) -> void:
	_face_health_display_to_camera()
	_refresh_health_display()


func apply_structure_damage(damage: int) -> bool:
	var client := _get_sim_sidecar_client()
	if client == null:
		return false
	if not client.has_method("apply_structure_damage"):
		return false

	return bool(client.call("apply_structure_damage", structure_kind, damage))


func get_team() -> String:
	return team


func get_armor_target_nodes() -> Array[Node3D]:
	if hitbox_area != null:
		return [hitbox_area]
	return [self]


func _get_sim_sidecar_client() -> Node:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return null
	return scene_root.get_node_or_null("SimSidecarClient")


func _current_health() -> int:
	var client := _get_sim_sidecar_client()
	if client != null and client.has_method("get_structure_health"):
		return int(client.call("get_structure_health", structure_kind))
	return max_health


func _setup_body_mesh() -> void:
	body_mesh = MeshInstance3D.new()
	body_mesh.name = "Body"
	var mesh := BoxMesh.new()
	mesh.size = cube_size
	body_mesh.mesh = mesh
	body_mesh.material_override = _build_body_material()
	add_child(body_mesh)


func _build_body_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = _body_color()
	return material


func _body_color() -> Color:
	if structure_kind == "base":
		return Color(0.96, 0.26, 0.20, 0.28)
	return Color(0.18, 0.62, 0.95, 0.28)


func _setup_hitbox() -> void:
	hitbox_area = HITBOX_SCRIPT.new()
	hitbox_area.name = "Hitbox"
	add_child(hitbox_area)
	hitbox_area.set("team", team)
	hitbox_area.set("hitbox_size", hitbox_size)
	hitbox_area.set("owner_target_path", hitbox_area.get_path_to(self))


func _setup_health_display() -> void:
	health_bar_anchor = Node3D.new()
	health_bar_anchor.name = "HealthBarAnchor"
	health_bar_anchor.position = Vector3(0.0, display_height, 0.0)
	add_child(health_bar_anchor)

	health_bar_back = MeshInstance3D.new()
	health_bar_back.name = "HealthBarBack"
	var back_mesh := QuadMesh.new()
	back_mesh.size = HEALTH_BAR_BACK_SIZE
	health_bar_back.mesh = back_mesh
	health_bar_back.material_override = _build_health_bar_material(
		Color(0.08, 0.08, 0.08, 1.0),
		HEALTH_BAR_BACK_PRIORITY
	)
	health_bar_anchor.add_child(health_bar_back)

	health_bar_fill = MeshInstance3D.new()
	health_bar_fill.name = "HealthBarFill"
	var fill_mesh := QuadMesh.new()
	fill_mesh.size = HEALTH_BAR_FILL_SIZE
	health_bar_fill.mesh = fill_mesh
	health_bar_fill.material_override = _build_health_bar_material(
		_fill_color(),
		HEALTH_BAR_FILL_PRIORITY
	)
	health_bar_fill.position = Vector3(0.0, 0.0, HEALTH_BAR_FILL_Z_OFFSET)
	health_bar_anchor.add_child(health_bar_fill)

	hp_label = Label3D.new()
	hp_label.name = "HealthLabel"
	hp_label.font_size = 28
	hp_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hp_label.position = Vector3(0.0, 0.22, 0.0)
	health_bar_anchor.add_child(hp_label)


func _fill_color() -> Color:
	if structure_kind == "base":
		return Color(0.95, 0.22, 0.18, 1.0)
	return Color(0.22, 0.72, 0.98, 1.0)


func _build_health_bar_material(color: Color, priority: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = priority
	material.albedo_color = color
	return material


func _refresh_health_display() -> void:
	if health_bar_fill == null or hp_label == null:
		return

	var hp := _current_health()
	var ratio := 0.0
	if max_health > 0:
		ratio = clampf(float(hp) / float(max_health), 0.0, 1.0)

	health_bar_fill.scale = Vector3(ratio, 1.0, 1.0)
	health_bar_fill.position = Vector3(
		-0.5 * HEALTH_BAR_FILL_SIZE.x * (1.0 - ratio),
		0.0,
		HEALTH_BAR_FILL_Z_OFFSET
	)
	hp_label.text = str(hp)


func _face_health_display_to_camera() -> void:
	if health_bar_anchor == null:
		return

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	health_bar_anchor.look_at(camera.global_position, Vector3.UP, true)
