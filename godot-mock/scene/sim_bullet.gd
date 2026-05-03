extends Area3D
## 模拟子弹，由 robots 射击生成。
## 沿 travel_direction 匀速运动，受重力影响下坠，碰撞到装甲板后造成伤害并自毁。
## 超过 lifetime 后自动销毁。

## 所属队伍 ("ally" / "enemy")。
@export var team := ""
## 飞行速度 (m/s)。
@export var speed := 25.0
## 最大存活时间 (s)，超时自动 queue_free。
@export var lifetime := 2.0
## 单发伤害值。
@export var damage := 20
## 飞行方向（世界空间单位向量）。
@export var travel_direction := Vector3.FORWARD
## 碰撞/渲染球体半径。
@export var radius := 0.1
## 重力倍率（1.0 = 标准重力加速度）。
@export var gravity_scale := 1.0

## 子弹独立碰撞层（第 4 bit）。
const BULLET_LAYER := 1 << 4
## 装甲板碰撞层（第 5 bit），子弹只检测此层。
const ARMOR_LAYER := 1 << 5

# 注意：变量名避免与 Area3D 内置 gravity 属性冲突，故使用 gravity_accel。
## 当前重力加速度值。
var gravity_accel : float = ProjectSettings.get_setting("physics/3d/default_gravity")
## 剩余存活时间 (s)。
var left_life := 0.0
## 当前飞行速度向量（含重力下坠分量）。
var current_velocity := Vector3.ZERO


func _ready() -> void:
	# 子弹作为检测体：monitoring 为 true 以接收 area_entered 信号。
	monitoring = true
	monitorable = false
	collision_layer = BULLET_LAYER
	collision_mask = ARMOR_LAYER
	left_life = lifetime
	area_entered.connect(_on_area_entered)

	# 无预制子节点时自动创建碰撞形状和网格。
	if get_child_count() == 0:
		_create_default_shape_and_mesh()

	# 归一化飞行方向，保证速度量级正确。
	travel_direction = travel_direction.normalized()
	if travel_direction.length() < 0.001:
		travel_direction = Vector3.FORWARD

	current_velocity = travel_direction * speed


func _physics_process(delta: float) -> void:
	left_life -= delta
	if left_life <= 0.0:
		queue_free()
		return

	# 重力影响：每个物理帧向下加速。
	current_velocity.y -= gravity_accel * gravity_scale * delta

	global_position += current_velocity * delta

	# 保持子弹朝向与运动方向一致。
	if current_velocity.length() > 0.1:
		look_at(global_position + current_velocity.normalized(), Vector3.UP)


## 碰撞回调：连接到 area_entered 信号。
## 进入装甲板碰撞体积时，调用其 on_bullet_hit 方法。
## 若返回 true（有效伤害），则销毁子弹。
func _on_area_entered(area: Area3D) -> void:
	if area == null or not is_instance_valid(area):
		return

	if area.has_method("on_bullet_hit"):
		var hit := bool(area.call("on_bullet_hit", damage, team))
		if hit:
			queue_free()


## 创建默认的 SphereShape 碰撞体和球体网格。
func _create_default_shape_and_mesh() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	add_child(shape)

	var mesh := MeshInstance3D.new()
	var bullet_mesh := SphereMesh.new()
	bullet_mesh.radius = radius
	bullet_mesh.height = radius * 2.0
	mesh.mesh = bullet_mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.86, 0.25, 1.0)
	mesh.material_override = mat
	add_child(mesh)
	
