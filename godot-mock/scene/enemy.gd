extends CharacterBody3D
## 敌方机器人，由键盘本地操控。
## 支持 WASD 移动、空格跳跃、J 键射击，以及第一/第三人称相机切换。
## 搭载四块装甲板受击判定，死亡后不可复活（仅停止运动）。

@export var external_camera: Camera3D
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
## 单发子弹伤害。
@export var bullet_damage := 20
## 初始/最大血量。
@export var max_health := 400
## 初始子弹数量。
@export var spawn_bullet := 200
## 跳跃输入动作名称。
@export var jump_action := "enemy_jump"
## 射击输入动作名称。
@export var fire_action := "enemy_fire"

const TEAM := "enemy"
const BULLET_SCRIPT := preload("res://scene/sim_bullet.gd")
const ARMOR_SCRIPT := preload("res://scene/sim_armor.gd")
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

@onready var shooter_node: Node3D = $gimbal/top_yaw/shooter


func _ready() -> void:
	_setup_armor_hitboxes()


func _physics_process(delta: float) -> void:
	# 减少射击冷却时间。
	fire_left = max(fire_left - delta, 0.0)

	# 死亡状态：完全静止，不响应任何输入。
	if dead:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	_tick_movement(delta)
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


## 处理键盘移动、跳跃和重力。
## 移动输入由键盘方向键驱动，支持加速度/阻力平滑过渡。
## 方向映射：key_up → -Z（前），key_right → +X（右）。
func _tick_movement(delta: float) -> void:
	# 读取键盘方向输入。
	var input_forward := Input.get_action_strength("key_up") - Input.get_action_strength("key_down")
	var input_right := Input.get_action_strength("key_right") - Input.get_action_strength("key_left")

	# 计算期望水平速度（归一化后乘以最大速度）。
	var desired := Vector3(-input_forward, 0.0, -input_right)
	if desired.length() > 1.0:
		desired = desired.normalized()
	desired *= move_speed

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

	var forward := _shooter_forward()
	bullet_node.set("travel_direction", forward)
	get_tree().current_scene.add_child(bullet_node)
	bullet_node.global_position = shooter_node.global_position + forward * 0.35
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

## 在第一人称（shooter 上的相机）和上帝视角（外部相机）之间切换。
func _toggle_camera() -> void:
	var fpv_cam = $gimbal/top_yaw/Camera3D

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
		
