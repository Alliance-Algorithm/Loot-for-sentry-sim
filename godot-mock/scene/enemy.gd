extends CharacterBody3D
## 敌方机器人，由键盘本地操控。
## 支持 WASD 移动、空格跳跃、J 键射击，以及第一/第三人称相机切换。
## 搭载四块装甲板受击判定，死亡后不可复活（仅停止运动）。

@export var external_camera: Camera3D
## 自瞄目标机器人。
@export var auto_aim_target: Node3D
## 底盘最大水平移动速度 (m/s)。
@export var move_speed := 4.2
## 底盘水平加速度 (m/s^2)。
@export var move_accel := 9.0
## 目标速度为零时的水平减速度（阻力）。
@export var move_drag := 7.0
## 跳跃初速度 (m/s)。
@export var jump_velocity := 5.2
## 射击冷却时间 (s)。
@export var fire_cooldown := 0.2
## 子弹飞行速度 (m/s)。
@export var bullet_speed := 24.0
## 子弹最大存活时间 (s)。
@export var bullet_lifetime := 2.0
## 子弹重力倍率，应与 sim_bullet.gd 中实际飞行参数一致。
@export var bullet_gravity_scale := 1.0
## 单发子弹伤害。
@export var bullet_damage := 20
## 初始/最大血量。
@export var max_health := 400000
## 初始子弹数量。
@export var spawn_bullet := 10000000

## 跳跃输入动作名称。
@export var jump_action := "enemy_jump"
## 射击输入动作名称。
@export var fire_action := "enemy_fire"
## 鼠标控制云台左右转动的灵敏度（弧度/像素）。
@export var mouse_yaw_sensitivity := 0.003
## 鼠标控制枪管上下俯仰的灵敏度（弧度/像素）。
@export var mouse_pitch_sensitivity := 0.003
## 枪管最大俯仰角（度）。
@export var max_pitch_degrees := 30.0
## 自瞄 yaw 跟踪速度（rad/s）。
@export var auto_aim_yaw_rate := 10.0
## 自瞄 pitch 跟踪速度（rad/s）。
@export var auto_aim_pitch_rate := 10.0
## 自瞄数值求解时允许的命中误差半径（米）。
@export var auto_aim_hit_tolerance := 0.30

const TEAM := "enemy"
const BULLET_SCRIPT := preload("res://scene/sim_bullet.gd")
const ARMOR_SCRIPT := preload("res://scene/sim_armor.gd")
const MUZZLE_OFFSET := 0.35
const AUTO_AIM_COARSE_PITCH_SAMPLES := 41
const AUTO_AIM_REFINEMENT_ROUNDS := 2
const AUTO_AIM_REFINEMENT_SAMPLES := 9
const AUTO_AIM_SIM_FALLBACK_HZ := 60.0
## 四块装甲板的子节点路径（用于挂载受击判定 Area）。
const ARMOR_NODE_PATHS := [
	"chassis/ban1/zhuangjia1",
	"chassis/ban4/zhuangjia2",
	"chassis/ban2/zhuangjia3",
	"chassis/ban3/zhuangjia4",
]

var gravity : float = ProjectSettings.get_setting("physics/3d/default_gravity")
var hp := max_health
var bullet := spawn_bullet
## 是否处于死亡状态（死亡后不可移动/射击）。
var dead := false
## 射击冷却剩余时间 (s)。
var fire_left := 0.0
## 上一帧空格是否按下（用于 JUMP 动作缺失时的回退检测）。
var jump_key_was_down := false
## 当前云台 yaw 角度（弧度）。
var yaw_angle := 0.0
## 当前枪管 pitch 角度（弧度）。
var pitch_angle := 0.0
## 自瞄总开关。
var auto_aim_enabled := false
## 当前锁定的目标装甲板。
var auto_aim_locked_target: Node3D = null
## 当前帧为最佳候选目标求得的 local pitch 解（弧度）。
var auto_aim_solution_pitch := 0.0
## 数值求解使用的模拟步长（秒），与子弹物理步长保持一致。
var auto_aim_sim_step_dt: float = 1.0 / AUTO_AIM_SIM_FALLBACK_HZ
## 左键仅用于重新捕获鼠标时，阻止本次按下同时触发射击。
var consume_left_click_fire_until_release := false

@onready var gimbal_yaw_node: Node3D = $gimbal
@onready var top_yaw_node: Node3D = $gimbal/top_yaw
@onready var pitch_pivot: Node3D = $gimbal/top_yaw/pitch_pivot
@onready var shooter_node: Node3D = $gimbal/top_yaw/pitch_pivot/shooter
@onready var fpv_cam: Camera3D = $gimbal/top_yaw/pitch_pivot/Camera3D


func _ready() -> void:
	_setup_armor_hitboxes()
	yaw_angle = gimbal_yaw_node.rotation.y
	pitch_angle = pitch_pivot.rotation.z
	var physics_ticks: float = float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second"))
	if physics_ticks > 0.0:
		auto_aim_sim_step_dt = 1.0 / physics_ticks
	_sync_mouse_capture()


func _physics_process(delta: float) -> void:
	# 减少射击冷却时间。
	fire_left = max(fire_left - delta, 0.0)

	# 死亡状态：完全静止，不响应任何输入。
	if dead:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	_tick_movement(delta)
	_tick_auto_aim(delta)
	_tick_fire()
	move_and_slide()
	# 记录空格状态，用于下一帧检测"刚刚按下"。
	jump_key_was_down = Input.is_key_pressed(KEY_SPACE)


## 受到子弹伤害，血量归零时进入死亡状态。
func apply_damage(amount: int, _armor_name: String = "") -> void:
	if dead:
		return
	hp = maxi(0, hp - max(amount, 0))
	if hp <= 0:
		dead = true
		velocity = Vector3.ZERO


func is_alive() -> bool:
	return not dead and hp > 0


func get_team() -> String:
	return TEAM


func get_armor_target_nodes() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for path in ARMOR_NODE_PATHS:
		var node := get_node_or_null(path)
		if node is Node3D:
			result.append(node)
	return result


## 第一人称下按相机水平朝向移动；外部相机下保持世界轴移动。
func _compute_desired_planar_movement(input_forward: float, input_right: float) -> Vector3:
	if fpv_cam.current:
		var basis := fpv_cam.global_basis.orthonormalized()
		var camera_forward := -basis.z
		var camera_right := basis.x
		camera_forward.y = 0.0
		camera_right.y = 0.0
		if camera_forward.length() < 0.001:
			camera_forward = Vector3.FORWARD
		else:
			camera_forward = camera_forward.normalized()
		if camera_right.length() < 0.001:
			camera_right = Vector3.RIGHT
		else:
			camera_right = camera_right.normalized()
		var desired := camera_forward * input_forward + camera_right * input_right
		if desired.length() > 1.0:
			desired = desired.normalized()
		return desired * move_speed

	var desired := Vector3(-input_forward, 0.0, -input_right)
	if desired.length() > 1.0:
		desired = desired.normalized()
	return desired * move_speed


## 处理键盘移动、跳跃和重力。
## 移动输入由键盘方向键驱动，支持加速度/阻力平滑过渡。
## 方向映射：key_up → -Z（前），key_right → +X（右）。
func _tick_movement(delta: float) -> void:
	# 读取键盘方向输入。
	var input_forward := Input.get_action_strength("key_up") - Input.get_action_strength("key_down")
	var input_right := Input.get_action_strength("key_right") - Input.get_action_strength("key_left")

	# 计算期望水平速度：第一人称下跟随视角水平朝向，外部相机下保持世界轴。
	var desired := _compute_desired_planar_movement(input_forward, input_right)

	# 加速度限制：当前速度向期望速度平滑过渡。
	var current := Vector3(velocity.x, 0.0, velocity.z)
	var dv := desired - current
	var step := move_accel * delta
	if dv.length() > step and step > 0.0:
		dv = dv.normalized() * step
	var next := current + dv
	# 无输入时施加阻力减速。
	if desired.length() < 0.01:
		next = next.move_toward(Vector3.ZERO, move_drag * delta)
	velocity.x = next.x
	velocity.z = next.z

	# 跳跃：支持 InputMap 动作或直接空格键回退检测。
	if _jump_just_pressed() and is_on_floor():
		velocity.y = jump_velocity
	elif not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0


func _tick_auto_aim(delta: float) -> void:
	auto_aim_locked_target = null

	if not auto_aim_enabled or not fpv_cam.current:
		return
	if auto_aim_target == null or not is_instance_valid(auto_aim_target):
		return
	if auto_aim_target.has_method("is_alive") and not bool(auto_aim_target.call("is_alive")):
		return

	auto_aim_solution_pitch = pitch_angle
	var target := _pick_auto_aim_target()
	if target == null:
		return

	if _track_auto_aim_target(target, auto_aim_solution_pitch, delta):
		auto_aim_locked_target = target


func _pick_auto_aim_target() -> Node3D:
	if not auto_aim_target.has_method("get_armor_target_nodes"):
		return null

	var armors: Array = auto_aim_target.call("get_armor_target_nodes")
	var visible_rect := get_viewport().get_visible_rect()
	var screen_center := visible_rect.position + visible_rect.size * 0.5
	var best: Node3D = null
	var best_d2 := INF

	for item in armors:
		if not (item is Node3D):
			continue
		var armor := item as Node3D
		if not _is_auto_aim_candidate_visible(armor, visible_rect):
			continue
		var solved_pitch: float = _solve_ballistic_pitch_local(armor.global_position)
		if solved_pitch == INF:
			continue
		var screen_pos := fpv_cam.unproject_position(armor.global_position)
		var d2 := screen_pos.distance_squared_to(screen_center)
		if d2 < best_d2:
			best_d2 = d2
			best = armor
			auto_aim_solution_pitch = solved_pitch

	return best


func _solve_ballistic_pitch_local(target_position: Vector3) -> float:
	if bullet_speed <= 0.001 or bullet_lifetime <= 0.0 or auto_aim_hit_tolerance <= 0.0:
		return INF

	var min_pitch: float = -deg_to_rad(max_pitch_degrees)
	var max_pitch: float = deg_to_rad(max_pitch_degrees)
	var best_pitch: float = 0.0
	var best_distance_sq: float = INF
	var pitch_span: float = max_pitch - min_pitch

	for i in range(AUTO_AIM_COARSE_PITCH_SAMPLES):
		var t: float = float(i) / float(AUTO_AIM_COARSE_PITCH_SAMPLES - 1)
		var candidate_pitch: float = lerpf(min_pitch, max_pitch, t)
		var candidate_distance_sq: float = _evaluate_ballistic_pitch_candidate_distance_sq(
			target_position,
			candidate_pitch
		)
		if candidate_distance_sq < best_distance_sq:
			best_distance_sq = candidate_distance_sq
			best_pitch = candidate_pitch

	if best_distance_sq == INF:
		return INF

	var coarse_step: float = pitch_span / float(AUTO_AIM_COARSE_PITCH_SAMPLES - 1)
	var refine_min: float = maxf(min_pitch, best_pitch - coarse_step)
	var refine_max: float = minf(max_pitch, best_pitch + coarse_step)

	for _round in range(AUTO_AIM_REFINEMENT_ROUNDS):
		var refine_best_pitch: float = best_pitch
		var refine_best_distance_sq: float = best_distance_sq
		for sample_idx in range(AUTO_AIM_REFINEMENT_SAMPLES):
			var t: float = float(sample_idx) / float(AUTO_AIM_REFINEMENT_SAMPLES - 1)
			var candidate_pitch: float = lerpf(refine_min, refine_max, t)
			var candidate_distance_sq: float = _evaluate_ballistic_pitch_candidate_distance_sq(
				target_position,
				candidate_pitch
			)
			if candidate_distance_sq < refine_best_distance_sq:
				refine_best_distance_sq = candidate_distance_sq
				refine_best_pitch = candidate_pitch

		best_pitch = refine_best_pitch
		best_distance_sq = refine_best_distance_sq
		var refine_step: float = (refine_max - refine_min) / float(AUTO_AIM_REFINEMENT_SAMPLES - 1)
		refine_min = maxf(min_pitch, best_pitch - refine_step)
		refine_max = minf(max_pitch, best_pitch + refine_step)

	var tolerance_sq: float = auto_aim_hit_tolerance * auto_aim_hit_tolerance
	if best_distance_sq > tolerance_sq:
		return INF
	return best_pitch


func _evaluate_ballistic_pitch_candidate_distance_sq(target_position: Vector3, local_pitch: float) -> float:
	var shooter_transform: Transform3D = _compute_candidate_shooter_transform(local_pitch)
	var forward: Vector3 = _forward_from_basis(shooter_transform.basis)
	var position: Vector3 = shooter_transform.origin + forward * MUZZLE_OFFSET
	var velocity: Vector3 = forward * bullet_speed
	var effective_gravity: float = gravity * bullet_gravity_scale
	var tolerance_sq: float = auto_aim_hit_tolerance * auto_aim_hit_tolerance
	var best_distance_sq: float = position.distance_squared_to(target_position)
	var step_count: int = maxi(1, int(ceil(bullet_lifetime / auto_aim_sim_step_dt)))

	for _step in range(step_count):
		var previous_position: Vector3 = position
		velocity.y -= effective_gravity * auto_aim_sim_step_dt
		position += velocity * auto_aim_sim_step_dt
		var candidate_distance_sq: float = _distance_sq_point_to_segment(
			target_position,
			previous_position,
			position
		)
		if candidate_distance_sq < best_distance_sq:
			best_distance_sq = candidate_distance_sq
		if best_distance_sq <= tolerance_sq:
			return best_distance_sq

	return best_distance_sq


func _compute_candidate_shooter_transform(local_pitch: float) -> Transform3D:
	var pitch_local: Transform3D = pitch_pivot.transform
	var local_scale: Vector3 = pitch_local.basis.get_scale()
	pitch_local.basis = Basis(Vector3(0.0, 0.0, 1.0), local_pitch).scaled(local_scale)
	return top_yaw_node.global_transform * pitch_local * shooter_node.transform


func _forward_from_basis(basis: Basis) -> Vector3:
	var forward: Vector3 = -basis.y
	if forward.length() < 0.001:
		return Vector3.FORWARD
	return forward.normalized()


func _distance_sq_point_to_segment(point: Vector3, segment_start: Vector3, segment_end: Vector3) -> float:
	var segment: Vector3 = segment_end - segment_start
	var segment_length_sq: float = segment.length_squared()
	if segment_length_sq < 0.000001:
		return point.distance_squared_to(segment_start)

	var t: float = clampf((point - segment_start).dot(segment) / segment_length_sq, 0.0, 1.0)
	var closest_point: Vector3 = segment_start + segment * t
	return point.distance_squared_to(closest_point)


func _is_auto_aim_candidate_visible(armor: Node3D, visible_rect: Rect2) -> bool:
	if fpv_cam.is_position_behind(armor.global_position):
		return false

	var screen_pos := fpv_cam.unproject_position(armor.global_position)
	if not visible_rect.has_point(screen_pos):
		return false

	var query := PhysicsRayQueryParameters3D.create(fpv_cam.global_position, armor.global_position)
	query.collide_with_areas = true
	query.exclude = [get_rid()]
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return true

	return _is_auto_aim_hit_target(result.get("collider"), armor)


func _is_auto_aim_hit_target(collider: Variant, armor: Node3D) -> bool:
	if not (collider is Node):
		return false

	var collider_node := collider as Node
	if collider_node == auto_aim_target or collider_node == armor:
		return true
	if auto_aim_target.is_ancestor_of(collider_node):
		return true
	if armor.is_ancestor_of(collider_node):
		return true
	if collider_node.is_ancestor_of(armor):
		return true
	return false


func _track_auto_aim_target(target: Node3D, desired_pitch: float, delta: float) -> bool:
	if desired_pitch == INF:
		return false

	var shooter_pos := shooter_node.global_position
	var to_target := target.global_position - shooter_pos
	var horizontal := Vector3(to_target.x, 0.0, to_target.z)

	if horizontal.length() >= 0.05:
		var forward := _shooter_forward()
		forward.y = 0.0
		if forward.length() < 0.001:
			forward = Vector3.FORWARD
		else:
			forward = forward.normalized()

		var target_dir := horizontal.normalized()
		var angle_error := atan2(forward.cross(target_dir).y, forward.dot(target_dir))
		var yaw_step: float = clampf(angle_error, -auto_aim_yaw_rate * delta, auto_aim_yaw_rate * delta)
		yaw_angle += yaw_step
		gimbal_yaw_node.rotation.y = yaw_angle

	pitch_angle = move_toward(pitch_angle, desired_pitch, auto_aim_pitch_rate * delta)
	pitch_pivot.rotation.z = pitch_angle
	return true


## 射击逻辑：检查冷却和子弹余量，沿 shooter 朝向生成子弹。
func _tick_fire() -> void:
	if not _fire_pressed():
		return
	if fire_left > 0.0 or bullet <= 0:
		return

	# 实例化并初始化子弹。
	var bullet_node := BULLET_SCRIPT.new()
	bullet_node.set("team", TEAM)
	bullet_node.set("speed", bullet_speed)
	bullet_node.set("damage", bullet_damage)
	bullet_node.set("lifetime", bullet_lifetime)
	bullet_node.set("gravity_scale", bullet_gravity_scale)

	var forward := _shooter_forward()
	bullet_node.set("travel_direction", forward)
	get_tree().current_scene.add_child(bullet_node)
	bullet_node.global_position = shooter_node.global_position + forward * MUZZLE_OFFSET
	bullet_node.look_at(bullet_node.global_position + forward, Vector3.UP)

	bullet -= 1
	fire_left = fire_cooldown


## 检测跳跃"刚刚按下"：优先使用 InputMap 动作，回退到空格键状态变化。
func _jump_just_pressed() -> bool:
	if InputMap.has_action(jump_action):
		return Input.is_action_just_pressed(jump_action)
	var down := Input.is_key_pressed(KEY_SPACE)
	return down and not jump_key_was_down


## 检测射击按键：优先 InputMap 动作，回退到 J 键。
func _fire_pressed() -> bool:
	if not consume_left_click_fire_until_release and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return true
	if InputMap.has_action(fire_action):
		return Input.is_action_pressed(fire_action)
	return Input.is_key_pressed(KEY_J)


## 计算 shooter 节点的世界空间前方向量。
## shooter 的局部 -Y 轴指向世界空间前方。
func _shooter_forward() -> Vector3:
	var forward := -shooter_node.global_basis.y
	if forward.length() < 0.001:
		return Vector3.FORWARD
	return forward.normalized()


## 为四块装甲板子节点挂载受击判定 Area3D。
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


## 输入处理：检测相机切换动作。
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("switch-camera"):
		_toggle_camera()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT and mouse_button.pressed:
			auto_aim_enabled = not auto_aim_enabled
			if not auto_aim_enabled:
				auto_aim_locked_target = null
			return

		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if not mouse_button.pressed:
				consume_left_click_fire_until_release = false
				return
			if fpv_cam.current and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				consume_left_click_fire_until_release = true
			return

	if event is InputEventMouseMotion and _can_control_gimbal_with_mouse():
		var motion := event as InputEventMouseMotion
		_apply_mouse_aim(motion.relative)

## 在第一人称（shooter 上的相机）和上帝视角（外部相机）之间切换。
func _toggle_camera() -> void:
	if not fpv_cam:
		print("未找到第一人称相机！")
		return

	if fpv_cam.current:
		if external_camera:
			external_camera.make_current()
			print("已切换至：上帝视角")
	else:
		fpv_cam.make_current()
		print("已切换至：第一人称视角")
	_sync_mouse_capture()


func _can_control_gimbal_with_mouse() -> bool:
	return fpv_cam.current and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and auto_aim_locked_target == null


func _apply_mouse_aim(relative: Vector2) -> void:
	yaw_angle -= relative.x * mouse_yaw_sensitivity
	pitch_angle -= relative.y * mouse_pitch_sensitivity
	pitch_angle = clampf(
		pitch_angle,
		-deg_to_rad(max_pitch_degrees),
		deg_to_rad(max_pitch_degrees)
	)
	gimbal_yaw_node.rotation.y = yaw_angle
	pitch_pivot.rotation.z = pitch_angle


func _sync_mouse_capture() -> void:
	if fpv_cam.current:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
