extends CharacterBody3D
## AI 控制的我方机器人。
## 通过 NavigationAgent3D 沿 navmesh 导航到目标点（由 Lua 决策端通过 TCP 下发），
## 搭载可扫描/自动瞄准的云台、四块装甲板受击判定、死亡/复活循环。

## 导航目标 Node3D（由 SimSidecarClient 根据 Lua nav_target 消息移动）。
@export var target_node: Node3D
## 底盘最大水平移动速度 (m/s)。
@export var move_speed := 2.5
## 底盘水平加速度 (m/s^2)。
@export var move_accel := 5.5
## 目标速度为零时的水平减速度（阻力）。
@export var move_drag := 4.0
## 底盘自旋最大速度 (rad/s，"spin" 模式使用)。
@export var chassis_spin_speed_max := 4.5
## 底盘自旋加速度 (rad/s^2)。
@export var chassis_spin_accel := 10.0
## 云台扫描最大转速 (rad/s)。
@export var gimbal_scan_speed_max := 2.8
## 云台旋转加速度 (rad/s^2)。
@export var gimbal_scan_accel := 8.0
## 云台锁定敌人后的追踪转速 (rad/s)。
@export var gimbal_track_turn_rate := 4.5
## 自动射击冷却时间 (s)。
@export var auto_fire_cooldown := 0.12
## 子弹飞行速度 (m/s)。
@export var bullet_speed := 25.0
## 子弹最大存活时间 (s)。
@export var bullet_lifetime := 2.0
## 单发子弹伤害。
@export var bullet_damage := 20
## 云台扫描射线长度。
@export var scan_range := 30.0
## 初始/最大血量。
@export var max_health := 400
## 初始子弹数。
@export var spawn_bullet := 100
## 初始金币数。
@export var spawn_gold := 0
## 死亡后到复活的时间间隔 (s)。
@export var respawn_delay := 5.0
## 复活时恢复的血量。
@export var respawn_health := 25
## 复活后护盾持续时间 (s)。
@export var respawn_shield_duration := 3.0
## 外部速度超控的有效持有时长 (s)。
@export var control_hold_seconds := 0.2

const TEAM := "ally"
const BULLET_SCRIPT := preload("res://scene/sim_bullet.gd")
const ARMOR_SCRIPT := preload("res://scene/sim_armor.gd")
const DEATH_FX_DURATION := 0.6
const SHIELD_PULSE_SPEED := 0.006
const SHIELD_PULSE_SCALE := 0.06
const HEALTH_BAR_ANCHOR_NAME := "HealthBarAnchor"
const HEALTH_BAR_BACK_NAME := "HealthBarBack"
const HEALTH_BAR_FILL_NAME := "HealthBarFill"
const HEALTH_BAR_HEIGHT := 1.0
const HEALTH_BAR_BACK_SIZE := Vector2(1.1, 0.14)
const HEALTH_BAR_FILL_SIZE := Vector2(1.0, 0.10)
const HEALTH_BAR_BACK_PRIORITY := 10
const HEALTH_BAR_FILL_PRIORITY := 11
const HEALTH_BAR_FILL_Z_OFFSET := -0.02
## 四块装甲板的子节点路径（用于挂载受击判定 Area）。
const ARMOR_NODE_PATHS := [
	"chassis/ban1/zhuangjia1",
	"chassis/ban4/zhuangjia2",
	"chassis/ban2/zhuangjia3",
	"chassis/ban3/zhuangjia4",
]

var gravity :float = ProjectSettings.get_setting("physics/3d/default_gravity")
## 底盘行为模式: "idle" 静止 / "spin" 自旋。
var chassis_mode := "idle"
## 云台控制来源: "manual" 手动 / "scan" 扫描 / "auto" 自动瞄准。
var gimbal_dominator := "manual"
## 外部速度超控向量 (X=前, Y=右)，由 Lua 遥控指令设置。
var external_chassis_vel := Vector2.ZERO
## 外部速度超控的剩余有效期 (s)。
var external_chassis_vel_ttl := 0.0

var current_chassis_spin_speed := 0.0
var current_scan_speed := 0.0
var fire_cooldown_left := 0.0

var hp := max_health
var bullet := spawn_bullet
var gold := spawn_gold
var is_dead := false
var dead_left := 0.0
var respawn_shield_left := 0.0

## 敌方机器人引用，供云台自动瞄准使用。
var enemy_target: Node3D = null

## 云台扫描视线 RayCast3D。
var scan_ray: RayCast3D = null
## 扫描射线的调试可视化线条（动态 ImmediateMesh）。
var scan_line: MeshInstance3D = null
## 死亡特效 Tween。
var death_fx_tween: Tween = null
## 护盾效果基准缩放。
var shield_fx_base_scale := Vector3.ONE
## 死亡特效基准缩放。
var death_burst_fx_base_scale := Vector3.ONE
## 头顶血条锚点。
var health_bar_anchor: Node3D = null
## 头顶血条背景。
var health_bar_back: MeshInstance3D = null
## 头顶血条红条。
var health_bar_fill: MeshInstance3D = null

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var chassis_node: Node3D = $chassis
@onready var gimbal_top_yaw: Node3D = $gimbal/top_yaw
@onready var shooter_node: Node3D = $gimbal/top_yaw/shooter
@onready var shield_fx: MeshInstance3D = $ShieldFX
@onready var death_burst_fx: MeshInstance3D = $DeathBurstFX


func _ready() -> void:
	_setup_scan_tools()
	_setup_armor_hitboxes()
	_setup_health_bar()
	shield_fx_base_scale = shield_fx.scale
	death_burst_fx_base_scale = death_burst_fx.scale
	_set_shield_fx_active(false)
	_reset_death_fx()
	_update_health_bar()
	_face_health_bar_to_camera()


func _physics_process(delta: float) -> void:
	_tick_death(delta)
	_tick_respawn_shield(delta)

	fire_cooldown_left = max(fire_cooldown_left - delta, 0.0)
	if external_chassis_vel_ttl > 0.0:
		external_chassis_vel_ttl = max(external_chassis_vel_ttl - delta, 0.0)

	if is_dead:
		# 死亡时停止水平移动，但重力仍然作用。
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		var desired_planar := _compute_desired_planar_velocity()
		_apply_planar_inertia(desired_planar, delta)
		_tick_chassis_spin(delta)
		_tick_gimbal(delta)

	# Gravity: only applied when not on floor (walk-off edges, stairs, etc.).
	if not is_on_floor():
		velocity.y -= gravity * delta

	move_and_slide()

	if is_dead:
		_hide_scan_line()

	_face_health_bar_to_camera()


## 设置敌方目标引用，供云台自动瞄准使用。
func set_enemy_target(target: Node3D) -> void:
	enemy_target = target


## 设置底盘模式 ("idle"/"spin")，由 Lua 控制指令调用。
func set_chassis_mode(mode: String) -> void:
	if is_dead:
		return
	chassis_mode = mode


## 设置云台控制源 ("manual"/"scan"/"auto")，由 Lua 控制指令调用。
func set_gimbal_dominator(dominator_name: String) -> void:
	if is_dead:
		return
	gimbal_dominator = dominator_name


## 手动设置云台 yaw 角度，仅在 gimbal_dominator == "manual" 时生效。
func set_gimbal_direction(angle: float) -> void:
	if is_dead or gimbal_dominator != "manual":
		return
	gimbal_top_yaw.rotation.y = angle


## 设置外部速度超控（Lua 遥控），超控持续 control_hold_seconds 秒后自动失效。
func set_external_chassis_velocity(x: float, y: float) -> void:
	if is_dead:
		return
	external_chassis_vel = Vector2(x, y)
	external_chassis_vel_ttl = control_hold_seconds


## 返回当前模拟资源状态，供 sidecar 上报给 Lua 决策端。
func get_sim_resource_state() -> Dictionary:
	return {
		"health": hp,
		"bullet": bullet,
		"gold": gold,
		"dead": is_dead,
	}


## 用 blackboard 传来的生命/子弹/金币值同步本机资源。
func sync_resources_from_blackboard(
	health: Variant,
	bullet_value: Variant,
	gold_value: Variant = null
) -> void:
	if health != null:
		hp = clampi(int(round(float(health))), 0, max_health)
	if bullet_value != null:
		bullet = maxi(0, int(round(float(bullet_value))))
	if gold_value != null:
		gold = maxi(0, int(round(float(gold_value))))
	_update_health_bar()


## 受到子弹伤害，血量归零时进入死亡状态。
func apply_damage(amount: int, _armor_name: String = "") -> void:
	if is_dead or _has_respawn_shield():
		return
	var next_hp : int= hp - max(amount, 0)
	hp = maxi(0, next_hp)
	_update_health_bar()
	if hp <= 0:
		_enter_death_state()


func is_alive() -> bool:
	return hp > 0 and not is_dead


func get_team() -> String:
	return TEAM


func get_armor_target_nodes() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for path in ARMOR_NODE_PATHS:
		var node := get_node_or_null(path)
		if node is Node3D:
			result.append(node)
	return result

func _compute_desired_planar_velocity() -> Vector3:

	if external_chassis_vel_ttl > 0.0:

		return Vector3(external_chassis_vel.x, 0.0, external_chassis_vel.y)


	if target_node:

		nav_agent.target_position = target_node.global_position



	if nav_agent.is_navigation_finished():

		return Vector3.ZERO


	var next_path_pos := nav_agent.get_next_path_position()

	var current_pos := global_position

	var flat := next_path_pos - current_pos

	flat.y = 0.0

	if flat.length() <= 0.001:

		return Vector3.ZERO

	look_at_target(next_path_pos, 8.0)

	return flat.normalized() * move_speed


func _apply_planar_inertia(desired: Vector3, delta: float) -> void:
	var current := Vector3(velocity.x, 0.0, velocity.z)
	var dv := desired - current
	var max_step := move_accel * delta
	if dv.length() > max_step and max_step > 0.0:
		dv = dv.normalized() * max_step
	var next := current + dv
	if desired.length() < 0.01:
		next = next.move_toward(Vector3.ZERO, move_drag * delta)
	velocity.x = next.x
	velocity.z = next.z


func _tick_chassis_spin(delta: float) -> void:
	var target_spin := 0.0
	if chassis_mode == "spin":
		target_spin = chassis_spin_speed_max
	current_chassis_spin_speed = move_toward(
		current_chassis_spin_speed, target_spin, chassis_spin_accel * delta
	)
	chassis_node.rotate_y(current_chassis_spin_speed * delta)


func _tick_gimbal(delta: float) -> void:
	match gimbal_dominator:
		"scan":
			_tick_scan_mode(delta)
		"auto":
			_tick_auto_mode(delta)
		_:
			current_scan_speed = move_toward(
				current_scan_speed, 0.0, gimbal_scan_accel * delta
			)
			_hide_scan_line()


func _tick_scan_mode(delta: float) -> void:
	current_scan_speed = move_toward(
		current_scan_speed, gimbal_scan_speed_max, gimbal_scan_accel * delta
	)
	gimbal_top_yaw.rotate_y(current_scan_speed * delta)
	_update_scan_ray_visual(true)


func _tick_auto_mode(delta: float) -> void:
	current_scan_speed = move_toward(current_scan_speed, 0.0, gimbal_scan_accel * delta)
	var lock := _track_enemy(delta)
	_update_scan_ray_visual(false)
	if lock and _can_fire():
		_fire_bullet(TEAM)
		bullet -= 1
		fire_cooldown_left = auto_fire_cooldown


func _track_enemy(delta: float) -> bool:
	if enemy_target == null:
		return false
	if enemy_target.has_method("is_alive") and not bool(enemy_target.call("is_alive")):
		return false

	var target := _pick_enemy_armor_target()
	if target == null:
		return false

	var shooter_pos := shooter_node.global_position
	var to_target := target.global_position - shooter_pos
	to_target.y = 0.0
	if to_target.length() < 0.05:
		return false

	var forward := _shooter_forward()
	forward.y = 0.0
	if forward.length() < 0.001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()

	var target_dir := to_target.normalized()
	var angle_error := atan2(forward.cross(target_dir).y, forward.dot(target_dir))
	var step : float = clamp(angle_error, -gimbal_track_turn_rate * delta, gimbal_track_turn_rate * delta)
	gimbal_top_yaw.rotate_y(step)

	return absf(angle_error) <= 0.08


func _pick_enemy_armor_target() -> Node3D:
	if enemy_target == null:
		return null
	if enemy_target.has_method("get_armor_target_nodes"):
		var armors: Array = enemy_target.call("get_armor_target_nodes")
		var best: Node3D = null
		var best_d2 := INF
		for item in armors:
			if item is Node3D:
				var n: Node3D = item
				var d2 := shooter_node.global_position.distance_squared_to(n.global_position)
				if d2 < best_d2:
					best_d2 = d2
					best = n
		return best
	return null


func _fire_bullet(team: String) -> void:
	var bullet_node := BULLET_SCRIPT.new()
	bullet_node.set("team", team)
	bullet_node.set("speed", bullet_speed)
	bullet_node.set("damage", bullet_damage)
	bullet_node.set("lifetime", bullet_lifetime)
	bullet_node.global_position = shooter_node.global_position + _shooter_forward() * 0.35
	bullet_node.look_at(bullet_node.global_position + _shooter_forward(), Vector3.UP)
	bullet_node.set("travel_direction", _shooter_forward())
	get_tree().current_scene.add_child(bullet_node)


func _shooter_forward() -> Vector3:
	var forward := -shooter_node.global_basis.y
	if forward.length() < 0.001:
		return Vector3.FORWARD
	return forward.normalized()


func _setup_scan_tools() -> void:
	scan_ray = RayCast3D.new()
	scan_ray.name = "ScanRay"
	scan_ray.target_position = Vector3(0.0, -scan_range, 0.0)
	scan_ray.enabled = true
	scan_ray.collide_with_areas = true
	scan_ray.collide_with_bodies = true
	shooter_node.add_child(scan_ray)

	scan_line = MeshInstance3D.new()
	scan_line.name = "ScanRayLine"
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.2, 1.0, 0.2, 0.95)
	scan_line.material_override = mat
	shooter_node.add_child(scan_line)
	_hide_scan_line()


func _update_scan_ray_visual(force_visible: bool) -> void:
	if scan_ray == null or scan_line == null:
		return

	var end_local := Vector3(0.0, -scan_range, 0.0)
	if scan_ray.is_colliding():
		var hit_global := scan_ray.get_collision_point()
		end_local = shooter_node.to_local(hit_global)

	var mesh := ImmediateMesh.new()
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(Vector3.ZERO)
	mesh.surface_add_vertex(end_local)
	mesh.surface_end()
	scan_line.mesh = mesh
	scan_line.visible = force_visible


func _hide_scan_line() -> void:
	if scan_line != null:
		scan_line.visible = false


func _has_respawn_shield() -> bool:
	return respawn_shield_left > 0.0


func _tick_respawn_shield(delta: float) -> void:
	if is_dead:
		if respawn_shield_left > 0.0:
			respawn_shield_left = 0.0
		_set_shield_fx_active(false)
		return

	if respawn_shield_left <= 0.0:
		_set_shield_fx_active(false)
		return

	respawn_shield_left = max(respawn_shield_left - delta, 0.0)
	if respawn_shield_left <= 0.0:
		_set_shield_fx_active(false)
		return

	_set_shield_fx_active(true)
	_update_shield_fx_visual()


func _can_fire() -> bool:
	return not is_dead and not _has_respawn_shield() and fire_cooldown_left <= 0.0 and bullet > 0


func _setup_armor_hitboxes() -> void:
	for path in ARMOR_NODE_PATHS:
		var armor_mesh := get_node_or_null(path)
		if armor_mesh == null:
			continue
		var area := ARMOR_SCRIPT.new()
		area.set("team", TEAM)
		area.set("armor_name", str(path.get_file()))
		armor_mesh.add_child(area)
		area.set("owner_robot_path", area.get_path_to(self))


func _setup_health_bar() -> void:
	health_bar_anchor = get_node_or_null(HEALTH_BAR_ANCHOR_NAME) as Node3D
	if health_bar_anchor == null:
		health_bar_anchor = Node3D.new()
		health_bar_anchor.name = HEALTH_BAR_ANCHOR_NAME
		health_bar_anchor.position = Vector3(0.0, HEALTH_BAR_HEIGHT, 0.0)
		add_child(health_bar_anchor)

	health_bar_back = health_bar_anchor.get_node_or_null(HEALTH_BAR_BACK_NAME) as MeshInstance3D
	if health_bar_back == null:
		health_bar_back = MeshInstance3D.new()
		health_bar_back.name = HEALTH_BAR_BACK_NAME
		var back_mesh := QuadMesh.new()
		back_mesh.size = HEALTH_BAR_BACK_SIZE
		health_bar_back.mesh = back_mesh
		health_bar_back.material_override = _build_health_bar_material(
			Color(0.08, 0.08, 0.08, 1.0),
			HEALTH_BAR_BACK_PRIORITY
		)
		health_bar_anchor.add_child(health_bar_back)

	health_bar_fill = health_bar_anchor.get_node_or_null(HEALTH_BAR_FILL_NAME) as MeshInstance3D
	if health_bar_fill == null:
		health_bar_fill = MeshInstance3D.new()
		health_bar_fill.name = HEALTH_BAR_FILL_NAME
		var fill_mesh := QuadMesh.new()
		fill_mesh.size = HEALTH_BAR_FILL_SIZE
		health_bar_fill.mesh = fill_mesh
		health_bar_fill.material_override = _build_health_bar_material(
			Color(0.92, 0.12, 0.12, 1.0),
			HEALTH_BAR_FILL_PRIORITY
		)
		health_bar_fill.position = Vector3(0.0, 0.0, HEALTH_BAR_FILL_Z_OFFSET)
		health_bar_anchor.add_child(health_bar_fill)


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


func _update_health_bar() -> void:
	if health_bar_anchor == null or health_bar_back == null or health_bar_fill == null:
		return

	var ratio: float = 0.0
	if max_health > 0:
		ratio = clampf(float(hp) / float(max_health), 0.0, 1.0)

	health_bar_fill.scale = Vector3(ratio, 1.0, 1.0)
	health_bar_fill.position = Vector3(
		-0.5 * HEALTH_BAR_FILL_SIZE.x * (1.0 - ratio),
		0.0,
		HEALTH_BAR_FILL_Z_OFFSET
	)


func _face_health_bar_to_camera() -> void:
	if health_bar_anchor == null:
		return

	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return

	health_bar_anchor.look_at(camera.global_position, Vector3.UP, true)


func _tick_death(delta: float) -> void:
	if not is_dead:
		return
	dead_left = max(dead_left - delta, 0.0)
	if dead_left <= 0.0:
		_respawn()


func _enter_death_state() -> void:
	is_dead = true
	dead_left = respawn_delay
	respawn_shield_left = 0.0
	velocity = Vector3.ZERO
	current_chassis_spin_speed = 0.0
	current_scan_speed = 0.0
	fire_cooldown_left = 0.0
	chassis_mode = "idle"
	gimbal_dominator = "manual"
	_set_shield_fx_active(false)
	_play_death_fx()


func _respawn() -> void:
	is_dead = false
	hp = respawn_health
	respawn_shield_left = respawn_shield_duration
	velocity = Vector3.ZERO
	chassis_mode = "idle"
	gimbal_dominator = "manual"
	current_chassis_spin_speed = 0.0
	current_scan_speed = 0.0
	_hide_scan_line()
	_set_shield_fx_active(respawn_shield_left > 0.0)
	_update_health_bar()


func _set_shield_fx_active(active: bool) -> void:
	if shield_fx == null:
		return

	shield_fx.visible = active
	if active:
		_update_shield_fx_visual()
		return

	shield_fx.scale = shield_fx_base_scale
	var shield_mat: StandardMaterial3D = shield_fx.material_override as StandardMaterial3D
	if shield_mat != null:
		var shield_color: Color = shield_mat.albedo_color
		shield_color.a = 0.24
		shield_mat.albedo_color = shield_color
		shield_mat.emission_energy_multiplier = 1.8


func _update_shield_fx_visual() -> void:
	if shield_fx == null or not shield_fx.visible:
		return

	var pulse_phase: float = float(Time.get_ticks_msec()) * SHIELD_PULSE_SPEED
	var pulse: float = 0.5 + 0.5 * sin(pulse_phase)
	shield_fx.scale = shield_fx_base_scale * (1.0 + SHIELD_PULSE_SCALE * pulse)

	var shield_mat: StandardMaterial3D = shield_fx.material_override as StandardMaterial3D
	if shield_mat != null:
		var shield_color: Color = shield_mat.albedo_color
		shield_color.a = lerpf(0.18, 0.34, pulse)
		shield_mat.albedo_color = shield_color
		shield_mat.emission_energy_multiplier = lerpf(1.4, 2.2, pulse)


func _play_death_fx() -> void:
	if death_burst_fx == null:
		return

	if death_fx_tween != null:
		death_fx_tween.kill()
		death_fx_tween = null

	_reset_death_fx()
	death_burst_fx.visible = true
	var death_mat: StandardMaterial3D = death_burst_fx.material_override as StandardMaterial3D
	if death_mat != null:
		death_mat.emission_energy_multiplier = 2.6
		_set_death_fx_alpha(0.9)

	death_fx_tween = create_tween()
	death_fx_tween.set_parallel(true)
	death_fx_tween.tween_property(
		death_burst_fx, "scale", death_burst_fx_base_scale * 3.0, DEATH_FX_DURATION
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	death_fx_tween.tween_method(_set_death_fx_alpha, 0.9, 0.0, DEATH_FX_DURATION)
	death_fx_tween.chain().tween_callback(_reset_death_fx)


func _set_death_fx_alpha(alpha: float) -> void:
	if death_burst_fx == null:
		return

	var death_mat: StandardMaterial3D = death_burst_fx.material_override as StandardMaterial3D
	if death_mat == null:
		return

	var death_color: Color = death_mat.albedo_color
	death_color.a = alpha
	death_mat.albedo_color = death_color
	death_mat.emission_energy_multiplier = 2.6 * alpha


func _reset_death_fx() -> void:
	if death_burst_fx == null:
		return

	death_burst_fx.visible = false
	death_burst_fx.scale = death_burst_fx_base_scale
	var death_mat: StandardMaterial3D = death_burst_fx.material_override as StandardMaterial3D
	if death_mat != null:
		var death_color: Color = death_mat.albedo_color
		death_color.a = 0.0
		death_mat.albedo_color = death_color
		death_mat.emission_energy_multiplier = 0.0
	death_fx_tween = null


func look_at_target(target_pos: Vector3, turn_speed: float) -> void:
	var direction := target_pos - global_position
	direction.y = 0.0
	if direction.length() <= 0.1:
		return
	var target_basis := Basis.looking_at(direction).rotated(Vector3.UP, PI/2.0)
	basis = basis.slerp(target_basis, clamp(turn_speed * get_physics_process_delta_time(), 0.0, 1.0))
