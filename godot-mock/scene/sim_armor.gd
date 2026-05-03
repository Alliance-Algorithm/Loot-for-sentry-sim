extends Area3D
## 模拟装甲板受击判定区域。
## 子弹通过碰撞层检测命中后，调用 owner_robot 的 apply_damage 方法造成伤害。
## 友军子弹不造成伤害（by from_team == team 过滤）。

## 所属队伍 ("ally" / "enemy")，用于友军伤害过滤。
@export var team := ""
## 装甲板名称（用于伤害回调标识）。
@export var armor_name := ""
## 装甲板所属机器人路径。
@export var owner_robot_path: NodePath
## 受击判定盒子尺寸。
@export var hitbox_size := Vector3(0.48, 0.42, 0.12)

## 装甲板独立碰撞层（第 5 bit）。
const ARMOR_LAYER := 1 << 5

## 装甲板所属机器人引用。
var owner_robot: Node = null


func _ready() -> void:
	# 启用区域检测，仅属于 ARMOR 碰撞层，不检测任何对象。
	monitoring = true
	monitorable = true
	collision_layer = ARMOR_LAYER
	collision_mask = 0
	add_to_group("sim_armor")

	# 解析所有者机器人引用。
	if owner_robot_path != NodePath():
		owner_robot = get_node_or_null(owner_robot_path)

	if owner_robot == null:
		# 沿父节点链向上查找 CharacterBody3D 作为所有者。
		owner_robot = _find_owner_robot()

	# 如果场景中没有预置碰撞形状，自动创建一个 BoxShape。
	if get_child_count() == 0:
		_create_default_shape()


## 子弹命中回调，由 sim_bullet.gd 的 area_entered 信号触发。
## 过滤友军子弹，然后向 owner_robot 转发伤害。
## @return: true 表示命中有效，子弹应销毁。
func on_bullet_hit(damage: int, from_team: String) -> bool:
	if from_team == team:
		return false
	if owner_robot != null and owner_robot.has_method("apply_damage"):
		owner_robot.call("apply_damage", damage, armor_name)
		return true
	return false


## 沿父节点链向上查找第一个 CharacterBody3D 节点作为所有者。
func _find_owner_robot() -> Node:
	var node: Node = self
	while node != null:
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	return null


## 创建默认碰撞形状（BoxShape3D）。
func _create_default_shape() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = hitbox_size
	shape.shape = box
	add_child(shape)
